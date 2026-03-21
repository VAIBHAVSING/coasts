/// `coast docker` command — run a docker command inside a coast instance's inner daemon.
///
/// Proxies docker commands into the DinD container, so `coast docker dev-1 ps`
/// runs `docker ps` against the inner Docker daemon. Everything after the
/// instance name is passed through as-is to `docker`.
///
/// When stdin is a TTY, spawns `docker exec -it` directly for full interactive
/// support (e.g., `coast docker dev-1 exec -it my-service sh`). Otherwise, uses
/// the daemon path to capture stdout/stderr.
use std::io::IsTerminal;

use anyhow::{bail, Result};
use clap::Args;

use coast_core::compose::{compose_context_for_build, shell_join};
use coast_core::protocol::{ExecRequest, Request, Response};

use super::exec::container_name;

/// Arguments for `coast docker`.
#[derive(Debug, Args)]
pub struct DockerArgs {
    /// Name of the coast instance.
    pub name: String,

    /// Run as container root/default user instead of the host UID:GID mapping.
    #[arg(long)]
    pub root: bool,

    /// Docker command and arguments to run (default: ps).
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub command: Vec<String>,
}

/// Resolve the docker command, defaulting to `ps` when no args given.
fn resolve_docker_command(args: &[String]) -> Vec<String> {
    let mut cmd = vec!["docker".to_string()];
    if args.is_empty() {
        cmd.push("ps".to_string());
    } else {
        cmd.extend(args.iter().cloned());
    }
    cmd
}

/// Resolve host uid:gid for docker exec user mapping.
fn host_uid_gid() -> Option<String> {
    #[cfg(unix)]
    {
        let uid = unsafe { nix::libc::getuid() };
        let gid = unsafe { nix::libc::getgid() };
        Some(format!("{uid}:{gid}"))
    }
    #[cfg(not(unix))]
    {
        None
    }
}

/// Build arguments for interactive `docker exec`.
fn build_interactive_docker_exec_args(
    container: &str,
    command: &[String],
    user_spec: Option<&str>,
) -> Vec<String> {
    let mut args = vec!["exec".to_string(), "-it".to_string()];
    if let Some(user) = user_spec {
        args.push("-u".to_string());
        args.push(user.to_string());
    }
    args.push(container.to_string());
    args.extend(command.iter().cloned());
    args
}

fn maybe_rewrite_compose_command(
    project: &str,
    build_id: Option<&str>,
    command: &[String],
) -> Vec<String> {
    if command.first().map(String::as_str) != Some("docker")
        || command.get(1).map(String::as_str) != Some("compose")
    {
        return command.to_vec();
    }

    let subcmd = if command.len() > 2 {
        shell_join(&command[2..])
    } else {
        "ps".to_string()
    };
    let ctx = compose_context_for_build(project, build_id);
    vec![
        "sh".to_string(),
        "-c".to_string(),
        ctx.compose_script(&subcmd),
    ]
}

/// Execute the `coast docker` command.
pub async fn execute(args: &DockerArgs, project: &str) -> Result<()> {
    let resolved_command = resolve_docker_command(&args.command);
    let build_id = super::resolve_instance_build_id(project, &args.name);
    let command = maybe_rewrite_compose_command(project, build_id.as_deref(), &resolved_command);

    // Interactive mode: stdin is a TTY → spawn docker exec -it directly
    // for full TTY passthrough without going through the daemon.
    if std::io::stdin().is_terminal() {
        let container = container_name(project, &args.name);
        let user_spec = if args.root { None } else { host_uid_gid() };
        let docker_args =
            build_interactive_docker_exec_args(&container, &command, user_spec.as_deref());
        let mut cmd = std::process::Command::new("docker");
        cmd.args(&docker_args);
        let status = cmd.status()?;
        if !status.success() {
            std::process::exit(status.code().unwrap_or(1));
        }
        return Ok(());
    }

    // Non-interactive: use daemon path (captures stdout/stderr as strings)
    let request = Request::Exec(ExecRequest {
        name: args.name.clone(),
        project: project.to_string(),
        service: None,
        root: args.root,
        command,
    });

    let response = super::send_request(request).await?;

    match response {
        Response::Exec(resp) => {
            if !resp.stdout.is_empty() {
                print!("{}", resp.stdout);
            }
            if !resp.stderr.is_empty() {
                eprint!("{}", resp.stderr);
            }

            if resp.exit_code != 0 {
                std::process::exit(resp.exit_code);
            }

            Ok(())
        }
        Response::Error(e) => {
            bail!("{}", e.error);
        }
        _ => {
            bail!("Unexpected response from daemon");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[derive(Debug, Parser)]
    struct TestCli {
        #[command(flatten)]
        args: DockerArgs,
    }

    #[test]
    fn test_docker_args_name_only() {
        let cli = TestCli::try_parse_from(["test", "dev-1"]).unwrap();
        assert_eq!(cli.args.name, "dev-1");
        assert!(!cli.args.root);
        assert!(cli.args.command.is_empty());
    }

    #[test]
    fn test_docker_args_with_simple_command() {
        let cli = TestCli::try_parse_from(["test", "dev-1", "ps"]).unwrap();
        assert_eq!(cli.args.name, "dev-1");
        assert_eq!(cli.args.command, vec!["ps"]);
    }

    #[test]
    fn test_docker_args_with_root_flag() {
        let cli = TestCli::try_parse_from(["test", "dev-1", "--root", "ps"]).unwrap();
        assert!(cli.args.root);
        assert_eq!(cli.args.command, vec!["ps"]);
    }

    #[test]
    fn test_docker_args_with_compose_command() {
        let cli = TestCli::try_parse_from(["test", "dev-1", "compose", "logs", "-f"]).unwrap();
        assert_eq!(cli.args.name, "dev-1");
        assert_eq!(cli.args.command, vec!["compose", "logs", "-f"]);
    }

    #[test]
    fn test_docker_args_with_flags() {
        let cli = TestCli::try_parse_from([
            "test",
            "dev-1",
            "images",
            "--format",
            "{{.Repository}}:{{.Tag}}",
        ])
        .unwrap();
        assert_eq!(cli.args.name, "dev-1");
        assert_eq!(
            cli.args.command,
            vec!["images", "--format", "{{.Repository}}:{{.Tag}}"]
        );
    }

    #[test]
    fn test_docker_args_missing_name() {
        let result = TestCli::try_parse_from(["test"]);
        assert!(result.is_err());
    }

    #[test]
    fn test_resolve_docker_command_empty_defaults_to_ps() {
        let cmd = resolve_docker_command(&[]);
        assert_eq!(cmd, vec!["docker", "ps"]);
    }

    #[test]
    fn test_resolve_docker_command_provided() {
        let cmd = resolve_docker_command(&["images".to_string(), "-a".to_string()]);
        assert_eq!(cmd, vec!["docker", "images", "-a"]);
    }

    #[test]
    fn test_resolve_docker_command_compose() {
        let cmd = resolve_docker_command(&[
            "compose".to_string(),
            "ps".to_string(),
            "--format".to_string(),
            "json".to_string(),
        ]);
        assert_eq!(cmd, vec!["docker", "compose", "ps", "--format", "json"]);
    }

    #[test]
    fn test_maybe_rewrite_compose_command_wraps_with_sh() {
        let cmd = maybe_rewrite_compose_command(
            "my-app",
            None,
            &[
                "docker".to_string(),
                "compose".to_string(),
                "ps".to_string(),
            ],
        );
        assert_eq!(cmd[0], "sh");
        assert_eq!(cmd[1], "-c");
        assert!(cmd[2].contains("/coast-override/docker-compose.coast.yml"));
        assert!(cmd[2].contains("docker compose -p coast-my-app"));
        assert!(cmd[2].contains("ps"));
    }

    #[test]
    fn test_maybe_rewrite_compose_command_leaves_raw_docker_alone() {
        let original = vec!["docker".to_string(), "ps".to_string()];
        let cmd = maybe_rewrite_compose_command("my-app", None, &original);
        assert_eq!(cmd, original);
    }

    #[test]
    fn test_build_interactive_docker_exec_args_with_user() {
        let args = build_interactive_docker_exec_args(
            "my-app-coasts-main",
            &["docker".to_string(), "ps".to_string()],
            Some("501:20"),
        );
        assert_eq!(
            args,
            vec![
                "exec",
                "-it",
                "-u",
                "501:20",
                "my-app-coasts-main",
                "docker",
                "ps",
            ]
        );
    }

    #[test]
    fn test_build_interactive_docker_exec_args_without_user() {
        let args = build_interactive_docker_exec_args(
            "my-app-coasts-main",
            &["docker".to_string(), "ps".to_string()],
            None,
        );
        assert_eq!(
            args,
            vec!["exec", "-it", "my-app-coasts-main", "docker", "ps"]
        );
    }
}
