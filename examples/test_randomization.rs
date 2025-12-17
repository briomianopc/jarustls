/// Simple test client to verify fingerprint randomization
///
/// This client makes multiple HTTPS connections to demonstrate
/// fingerprint randomization in action.
///
/// Usage:
///   cargo run --example test_randomization [--with-randomization]

use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::Arc;
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    let enable_randomization = args.len() > 1 && args[1] == "--with-randomization";

    println!("=================================");
    println!("Fingerprint Randomization Test");
    println!("=================================");
    println!();
    println!("Randomization: {}", if enable_randomization { "ENABLED" } else { "DISABLED" });
    println!();

    // Create root certificate store
    let mut root_store = rustls::RootCertStore::empty();
    root_store.extend(
        webpki_roots::TLS_SERVER_ROOTS
            .iter()
            .cloned()
    );

    // Create client config
    let mut config = rustls::ClientConfig::builder()
        .with_root_certificates(root_store)
        .with_no_client_auth()
        .expect("Failed to build client config");

    // Enable randomization if requested
    config.randomize_fingerprint = enable_randomization;

    let config = Arc::new(config);

    // Test domain (uses standard TLS, not ECH)
    let domain = "www.example.com";
    let port = 443;

    println!("Target: {}:{}", domain, port);
    println!();
    println!("Making 5 connections...");
    println!();

    // Make multiple connections
    for i in 1..=5 {
        println!("Connection #{}", i);
        
        match make_connection(&config, domain, port) {
            Ok(_) => println!("  ✅ Success"),
            Err(e) => println!("  ❌ Failed: {}", e),
        }
        
        // Small delay between connections
        std::thread::sleep(std::time::Duration::from_millis(500));
    }

    println!();
    println!("=================================");
    println!("Test Complete");
    println!("=================================");
    println!();
    
    if enable_randomization {
        println!("✅ Randomization was ENABLED");
        println!();
        println!("Each connection should have:");
        println!("  - Different cipher suite order");
        println!("  - Random padding (70% probability)");
        println!("  - Randomized extension order");
        println!();
        println!("To verify:");
        println!("  sudo ./tools/verify_ja3.sh any 30");
        println!("  # Then run this test again");
    } else {
        println!("⚠️  Randomization was DISABLED");
        println!();
        println!("All connections have identical fingerprints.");
        println!();
        println!("To enable randomization:");
        println!("  cargo run --example test_randomization --with-randomization");
    }
    println!();
}

fn make_connection(
    config: &Arc<rustls::ClientConfig>,
    domain: &str,
    port: u16,
) -> Result<(), Box<dyn std::error::Error>> {
    // Create TCP connection
    let addr = format!("{}:{}", domain, port);
    let mut sock = TcpStream::connect(&addr)?;

    // Create TLS connection
    let server_name = rustls::pki_types::ServerName::try_from(domain)?
        .to_owned();
    let mut conn = rustls::ClientConnection::new(config.clone(), server_name)?;

    // Complete TLS handshake
    let mut tls = rustls::Stream::new(&mut conn, &mut sock);

    // Send HTTP request
    tls.write_all(
        format!(
            "GET / HTTP/1.1\r\n\
             Host: {}\r\n\
             Connection: close\r\n\
             \r\n",
            domain
        )
        .as_bytes(),
    )?;

    // Read response (just first few bytes to verify connection)
    let mut response = vec![0u8; 1024];
    let n = tls.read(&mut response)?;

    // Check if we got a valid HTTP response
    if n > 0 && response.starts_with(b"HTTP/") {
        Ok(())
    } else {
        Err("Invalid HTTP response".into())
    }
}
