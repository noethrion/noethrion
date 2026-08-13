// Contact-intent tracking for noethrion.com.
//
// The analytics property and its contact_click goal have existed for some
// time, but no page ever carried the counter, so the goal recorded nothing.
// This file supplies the missing half: the event itself.
//
// Kept as a separate file rather than an inline block so that a future
// Content-Security-Policy on this domain does not silently disable it —
// the same failure mode already cost another site two months of blank
// reports.
//
// One delegated listener covers the whole page: a contact link added later
// is counted without touching this file.
(function () {
  document.addEventListener(
    "click",
    function (e) {
      var a = e.target && e.target.closest && e.target.closest("a[href]");
      if (!a) return;
      var h = a.getAttribute("href") || "";
      var kind = /^mailto:/i.test(h)
        ? "email"
        : /^tel:/i.test(h)
          ? "phone"
          : /(t\.me|wa\.me|telegram\.me|whatsapp)/i.test(h)
            ? "messenger"
            : /(linkedin\.com|instagram\.com|x\.com|twitter\.com)/i.test(h)
              ? "social"
              : "";
      if (!kind) return;
      try {
        if (window.plausible) window.plausible("contact_click", { props: { kind: kind } });
      } catch (err) {
        // Analytics must never stand between a reader and getting in touch.
      }
    },
    true, // capture, so the event is recorded before navigation begins
  );
})();
