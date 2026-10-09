// Renders the Markdown file named in <body data-src> with marked.
(async () => {
  const src = document.body.dataset.src;
  const main = document.querySelector("main");
  try {
    const res = await fetch(src, {cache: "no-cache"});
    if (!res.ok) throw new Error(res.status);
    const md = (await res.text()).replace(/<!--[\s\S]*?-->/g, "");
    main.innerHTML = marked.parse(md);
    const h1 = main.querySelector("h1");
    if (h1) document.title = h1.textContent;
  } catch (e) {
    main.textContent = "This page could not be loaded. Please try again later.";
  }
})();
