//! Remote VM management and SSH tunnel infrastructure.
//!
//! This module provides:
//! - SSH tunnel lifecycle management
//! - Remote coastd setup/installation
//! - Connection health monitoring

pub mod setup;
pub mod tunnel;

pub use setup::RemoteSetup;
pub use tunnel::TunnelManager;
