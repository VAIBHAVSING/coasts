/// `coast skills-prompt` — print the Coast runtime skills prompt for AI coding agents.
///
/// This command is standalone and does not require the daemon to be running.
/// The prompt text is compiled into the binary via `include_str!()`.
use anyhow::Result;
use clap::Args;

const PROMPT: &str = include_str!("../../../docs/skills_prompt.txt");

/// Arguments for `coast skills-prompt`.
#[derive(Debug, Args)]
pub struct SkillsPromptArgs {}

/// Print the skills prompt to stdout.
pub async fn execute(_args: &SkillsPromptArgs) -> Result<()> {
    print!("{PROMPT}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[derive(Debug, Parser)]
    struct TestCli {
        #[command(flatten)]
        args: SkillsPromptArgs,
    }

    #[test]
    fn test_skills_prompt_args_parse() {
        let cli = TestCli::try_parse_from(["test"]).unwrap();
        let _ = cli.args;
    }

    #[test]
    fn test_prompt_text_is_non_empty() {
        assert!(
            !PROMPT.is_empty(),
            "skills_prompt.txt should be compiled into the binary"
        );
    }

    #[test]
    fn test_prompt_text_contains_key_commands() {
        assert!(PROMPT.contains("coast lookup"));
        assert!(PROMPT.contains("coast exec"));
        assert!(PROMPT.contains("coast logs"));
    }
}
