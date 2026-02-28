(async () => {
	const PASS_HASH = "__HASH_KEY_LOCALE__";

	const raw = window.location.hash.slice(1);
	if (!raw) { document.documentElement.style.display = "none"; return; }

	const encoded = new TextEncoder().encode(raw);
	const hashBuf = await crypto.subtle.digest("SHA-256", encoded);
	const hashHex = Array.from(new Uint8Array(hashBuf))
	.map(b => b.toString(16).padStart(2, "0")).join("");

	if (hashHex !== PASS_HASH) {
		document.documentElement.style.display = "none";
	}

})();
