(async () => {
    const CIPHERTEXT = "__ENCRYPTED_PAYLOAD__";
    const raw = window.location.hash.slice(1);
    if (!raw) { document.documentElement.style.display = "none"; return; }

    const bytes = Uint8Array.from(atob(CIPHERTEXT), c => c.charCodeAt(0));
    const salt  = bytes.slice(0, 16);
    const iv    = bytes.slice(16, 28);
    const tag   = bytes.slice(28, 44);
    const data  = bytes.slice(44);

    const keyMaterial = await crypto.subtle.importKey(
        "raw", new TextEncoder().encode(raw), "PBKDF2", false, ["deriveKey"]
    );
    const key = await crypto.subtle.deriveKey(
        { name: "PBKDF2", salt, iterations: 100_000, hash: "SHA-256" },
        keyMaterial,
        { name: "AES-GCM", length: 256 },
        false, ["decrypt"]
    );

    // AES-GCM expects ciphertext + tag concatenated
    const combined = new Uint8Array([...data, ...tag]);

    try {
        const plaintext = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, combined);
        document.getElementById("main-content").innerHTML = new TextDecoder().decode(plaintext);
    } catch {
        document.documentElement.style.display = "none";
    }
})();
