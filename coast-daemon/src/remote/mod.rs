//! Remote VM management and SSH tunnel infrastructure.
//!
//! This module provides:
//! - SSH tunnel lifecycle management
//! - Remote coastd setup/installation
//! - Connection health monitoring
//! - Mutagen file synchronization

pub mod mutagen;
pub mod setup;
pub mod tunnel;

pub use mutagen::MutagenManager;
pub use setup::RemoteSetup;
pub use tunnel::TunnelManager;
