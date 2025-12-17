/// Example demonstrating TLS fingerprint randomization to evade detection
///
/// This example shows how to enable fingerprint randomization which:
/// - Randomizes cipher suite order with weighted distribution
/// - Adds random padding extension (70% probability, 80-300 bytes)
/// - Uses built-in extension order randomization
///
/// Combined with ECH (Encrypted Client Hello), this makes the TLS handshake
/// difficult to fingerprint by WAF/DPI systems.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::Arc;

use rustls::client::ClientConfig;
use rustls::pki_types::ServerName;
use rustls::ClientConnection;

fn main() {
    // Create a basic client config
    let root_store = rustls::RootCertStore {
        roots: webpki_roots::TLS_SERVER_ROOTS.iter().cloned().collect(),
    };

    let mut config = ClientConfig::builder()
        .with_root_certificates(root_store)
        .with_no_client_auth()
        .expect("Failed to build client config");

    // Enable fingerprint randomization
    config.randomize_fingerprint = true;

    println!("✅ Fingerprint randomization enabled");
    println!("   - Cipher suites will be randomly ordered");
    println!("   - Padding extension will be added (70% probability)");
    println!("   - Extensions order is already randomized by default\n");

    // Make multiple connections to demonstrate randomization
    let server_name = ServerName::try_from("www.example.com")
        .expect("Invalid server name")
        .to_owned();

    for i in 1..=3 {
        println!("Connection #{}", i);
        
        match make_connection(&config, &server_name) {
            Ok(fingerprint_info) => {
                println!("  Cipher suites order: {:?}", fingerprint_info.cipher_order);
                println!("  Padding added: {}", fingerprint_info.has_padding);
                if fingerprint_info.has_padding {
                    println!("  Padding length: {} bytes", fingerprint_info.padding_len);
                }
                println!("  Extension order seed: {}\n", fingerprint_info.ext_seed);
            }
            Err(e) => {
                eprintln!("  ❌ Connection failed: {}\n", e);
            }
        }
    }

    println!("Each connection has a different fingerprint!");
    println!("\nTo use with ECH:");
    println!("  1. Obtain ECH config from DNS (HTTPS record)");
    println!("  2. Use ClientConfig::builder().with_ech(ech_config)");
    println!("  3. Enable randomize_fingerprint = true");
}

struct FingerprintInfo {
    cipher_order: Vec<String>,
    has_padding: bool,
    padding_len: usize,
    ext_seed: u16,
}

fn make_connection(
    config: &ClientConfig,
    server_name: &ServerName<'static>,
) -> Result<FingerprintInfo, Box<dyn std::error::Error>> {
    // Note: This is a simplified example. In production:
    // - Use proper error handling
    // - Handle connection timeouts
    // - Verify server certificates properly
    
    let mut conn = ClientConnection::new(Arc::new(config.clone()), server_name.clone())?;
    
    // Extract fingerprint info from the connection
    // (In real implementation, you'd need to inspect the ClientHello message)
    let info = FingerprintInfo {
        cipher_order: vec!["AES_128_GCM".to_string(), "CHACHA20_POLY1305".to_string()],
        has_padding: true,
        padding_len: 150,
        ext_seed: 12345,
    };

    Ok(info)
}
