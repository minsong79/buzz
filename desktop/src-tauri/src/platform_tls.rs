//! Outbound TLS for native Desktop connections.
//!
//! The live relay socket, huddle audio, and pairing all use rustls via
//! `tokio-tungstenite`. The crate's default `webpki-roots` store only trusts
//! public CAs, so a corporate TLS-inspection proxy (a company FORWARDTRUST
//! CA in the OS keychain) fails while curl and Safari succeed.
//!
//! `rustls-platform-verifier` uses the same OS trust store as the rest of the
//! machine, including enterprise roots. reqwest 0.13 already does this for
//! HTTP; this module applies it to WebSocket so both stacks agree.

use std::sync::{Arc, OnceLock};

use rustls::ClientConfig;
use rustls_platform_verifier::BuilderVerifierExt;
use tokio::net::TcpStream;
use tokio_tungstenite::{
    connect_async_tls_with_config, Connector, MaybeTlsStream, WebSocketStream,
};

/// Install a process-wide rustls CryptoProvider. Dependencies enable more than
/// one provider; rustls refuses to auto-select. Safe to call more than once.
pub(crate) fn install_crypto_provider() {
    let _ = rustls::crypto::aws_lc_rs::default_provider().install_default();
}

fn platform_tls_connector() -> Result<Connector, String> {
    static CONFIG: OnceLock<Arc<ClientConfig>> = OnceLock::new();
    if let Some(config) = CONFIG.get() {
        return Ok(Connector::Rustls(Arc::clone(config)));
    }

    install_crypto_provider();
    let config = Arc::new(
        ClientConfig::builder()
            .with_platform_verifier()
            .map_err(|error| format!("platform TLS verifier: {error}"))?
            .with_no_client_auth(),
    );
    Ok(Connector::Rustls(Arc::clone(
        CONFIG.get_or_init(|| Arc::clone(&config)),
    )))
}

/// Open a WebSocket with OS trust roots (public CAs plus enterprise roots).
pub(crate) async fn connect_relay_websocket(
    url: &str,
) -> Result<WebSocketStream<MaybeTlsStream<TcpStream>>, String> {
    let connector = platform_tls_connector()?;
    let (stream, _) = connect_async_tls_with_config(url, None, false, Some(connector))
        .await
        .map_err(|error| error.to_string())?;
    Ok(stream)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn platform_tls_connector_builds() {
        install_crypto_provider();
        platform_tls_connector().expect("platform TLS connector must build");
    }
}
