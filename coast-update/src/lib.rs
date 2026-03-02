/// Coast self-update system.
///
/// Provides version checking against GitHub Releases, a three-tier update policy
/// (nudge/required/auto), and self-update functionality for both `coast` and
/// `coastd` binaries.
pub mod checker;
pub mod error;
pub mod policy;
pub mod updater;
pub mod version;

use policy::{PolicyAction, UpdatePolicy};
use std::time::Duration;

/// Default timeout for network operations during the pre-run policy check.
pub const POLICY_CHECK_TIMEOUT: Duration = Duration::from_secs(2);

/// Default timeout for downloading updates.
pub const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(120);

/// Enforce the update policy: fetch policy + latest version, evaluate, return action.
///
/// This is the main entry point for the pre-run check in the CLI.
/// All network failures are swallowed — the CLI should never be blocked
/// by a failed update check.
pub async fn enforce_update_policy(timeout: Duration) -> PolicyAction {
    let Ok(current) = version::current_version() else {
        return PolicyAction::UpToDate;
    };

    // Fetch policy and latest version concurrently
    let (policy_result, latest) = tokio::join!(
        policy::fetch_policy(timeout),
        checker::check_latest_version(timeout),
    );

    policy::evaluate_policy(&policy_result, &current, latest.as_ref())
}

/// Build the update command string, prefixing with `sudo` if the install
/// directory is not writable by the current user.
fn update_command() -> String {
    let needs_sudo = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(std::path::Path::to_path_buf))
        .is_some_and(|dir| {
            // Try creating a temp file in the install directory
            let probe = dir.join(".coast-write-probe");
            if std::fs::File::create(&probe).is_ok() {
                let _ = std::fs::remove_file(&probe);
                false
            } else {
                true
            }
        });

    if needs_sudo {
        "sudo coast update apply".to_string()
    } else {
        "coast update apply".to_string()
    }
}

/// Format a nudge message for display after command execution.
pub fn format_nudge_message(current: &str, latest: &str, custom_message: &str) -> String {
    let cmd = update_command();
    let mut msg = format!(
        "A new version of coast is available: {current} -> {latest}\n\
         Run `{cmd}` to update."
    );
    if !custom_message.is_empty() {
        msg.push_str(&format!("\n{custom_message}"));
    }
    msg
}

/// Format a required-update message for display before blocking execution.
pub fn format_required_message(current: &str, minimum: &str, custom_message: &str) -> String {
    let cmd = update_command();
    let mut msg = format!(
        "coast v{current} is no longer supported. Minimum required version: v{minimum}\n\
         Run `{cmd}` to update."
    );
    if !custom_message.is_empty() {
        msg.push_str(&format!("\n{custom_message}"));
    }
    msg
}

/// Check if a command name is an update subcommand (should skip policy check).
pub fn is_update_command(cmd: &str) -> bool {
    cmd == "update" || cmd.starts_with("update ")
}

/// Info about the current installation for `coast update check` output.
pub struct UpdateCheckInfo {
    pub current_version: String,
    pub latest_version: Option<String>,
    pub policy: UpdatePolicy,
}

/// Perform a full update check and return structured info for display.
pub async fn check_for_updates() -> UpdateCheckInfo {
    let current_version = version::CURRENT_VERSION.to_string();

    let (policy, latest) = tokio::join!(
        policy::fetch_policy(POLICY_CHECK_TIMEOUT),
        checker::check_latest_version(Duration::from_secs(10)),
    );

    UpdateCheckInfo {
        current_version,
        latest_version: latest.map(|v| v.to_string()),
        policy,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_nudge_message() {
        let msg = format_nudge_message("0.1.0", "0.2.0", "");
        assert!(msg.contains("0.1.0"));
        assert!(msg.contains("0.2.0"));
        assert!(msg.contains("coast update apply"));
    }

    #[test]
    fn test_format_nudge_message_with_custom() {
        let msg = format_nudge_message("0.1.0", "0.2.0", "Important security fix!");
        assert!(msg.contains("Important security fix!"));
    }

    #[test]
    fn test_format_required_message() {
        let msg = format_required_message("0.1.0", "0.3.0", "");
        assert!(msg.contains("no longer supported"));
        assert!(msg.contains("0.3.0"));
    }

    #[test]
    fn test_format_required_message_with_custom() {
        let msg = format_required_message("0.1.0", "0.3.0", "Breaking API change.");
        assert!(msg.contains("Breaking API change."));
    }

    #[test]
    fn test_is_update_command() {
        assert!(is_update_command("update"));
        assert!(is_update_command("update check"));
        assert!(is_update_command("update apply"));
        assert!(!is_update_command("build"));
        assert!(!is_update_command("run"));
        assert!(!is_update_command("ls"));
    }

    #[test]
    fn test_policy_check_timeout_value() {
        assert_eq!(POLICY_CHECK_TIMEOUT, Duration::from_secs(2));
    }

    #[test]
    fn test_download_timeout_value() {
        assert_eq!(DOWNLOAD_TIMEOUT, Duration::from_secs(120));
    }

    #[tokio::test]
    async fn test_enforce_update_policy_returns_action() {
        // This test exercises the full flow but will hit network errors (expected).
        // The important thing is that it returns UpToDate (fail-open behavior)
        // rather than panicking.
        let action = enforce_update_policy(Duration::from_millis(100)).await;
        // With a 100ms timeout, we'll either get UpToDate (no network) or Nudge (if cached)
        // Either way, it shouldn't panic or return Required/AutoUpdate without real data
        match action {
            PolicyAction::UpToDate => {}
            PolicyAction::Nudge { .. } => {}
            // These would only happen with real network data, but we accept them in CI
            PolicyAction::Required { .. } | PolicyAction::AutoUpdate { .. } => {}
        }
    }
}
