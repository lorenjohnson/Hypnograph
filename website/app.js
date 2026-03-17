(() => {
  const breadcrumbEl = document.getElementById("breadcrumb");
  const documentEl = document.getElementById("document");
  const docsSidebarEl = document.getElementById("docs-sidebar");
  const docsTreeEl = document.getElementById("docs-tree");

  if (!breadcrumbEl || !documentEl || !docsSidebarEl || !docsTreeEl) {
    return;
  }

  const TREE_OPEN_STATE_KEY = "hypnograph.docsTree.open.v1";
  const resolvedDocPath = resolveDocPath(window.location.pathname);
  const currentRelativeDocPath = resolvedDocPath.replace(/^\/docs\//, "");
  const isHomepage = window.location.pathname.replace(/\/+$/, "") === "";
  const markdownUtils = window.markdownit().utils;
  const openTreePaths = loadOpenTreePaths();

  if (isHomepage) {
    document.body.classList.add("homepage-route");
  }

  let lastText = "";

  const markdown = window.markdownit({
    html: true,
    xhtmlOut: true,
    breaks: true,
    linkify: true,
    typographer: true,
    highlight(code, language) {
      if (window.hljs && language && window.hljs.getLanguage(language)) {
        try {
          return "<pre class=\"hljs\"><code>" + window.hljs.highlight(code, { language, ignoreIllegals: true }).value + "</code></pre>";
        } catch (_) {}
      }
      if (window.hljs) {
        try {
          return "<pre class=\"hljs\"><code>" + window.hljs.highlightAuto(code).value + "</code></pre>";
        } catch (_) {}
      }
      return "<pre><code>" + markdownUtils.escapeHtml(code) + "</code></pre>";
    }
  });

  markdown.use(window.markdownitTaskLists, {
    enabled: false
  });

  function loadOpenTreePaths() {
    try {
      const raw = localStorage.getItem(TREE_OPEN_STATE_KEY);
      if (!raw) {
        return new Set();
      }
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) {
        return new Set();
      }
      return new Set(parsed.filter((path) => typeof path === "string"));
    } catch (_) {
      return new Set();
    }
  }

  function saveOpenTreePaths() {
    try {
      localStorage.setItem(TREE_OPEN_STATE_KEY, JSON.stringify(Array.from(openTreePaths).sort()));
    } catch (_) {}
  }

  function updateOpenTreePath(path, isOpen) {
    if (!path) {
      return;
    }
    if (isOpen) {
      openTreePaths.add(path);
    } else {
      openTreePaths.delete(path);
    }
    saveOpenTreePaths();
  }

  function stripFrontMatter(text) {
    const frontMatterPattern = /^---\r?\n[\s\S]*?\r?\n---(?:\r?\n|$)/;
    return text.replace(frontMatterPattern, "");
  }

  function resolveDocPath(pathname) {
    const normalizedPath = pathname.replace(/\/+$/, "");

    if (normalizedPath === "" || normalizedPath === "/") {
      return "/docs/collaborators.md";
    }

    if (normalizedPath.startsWith("/docs/")) {
      return normalizedPath.endsWith(".md") ? normalizedPath : normalizedPath + ".md";
    }

    return "/docs" + (normalizedPath.endsWith(".md") ? normalizedPath : normalizedPath + ".md");
  }

  function titleCaseSegment(segment) {
    return segment
      .replace(/\.md$/i, "")
      .replace(/[-_]+/g, " ")
      .replace(/\b\w/g, (char) => char.toUpperCase());
  }

  function renderBreadcrumb(pathname) {
    const normalizedPath = pathname.replace(/\/+$/, "");
    const routePath = normalizedPath === "" ? "/" : normalizedPath;
    const rawSegments = routePath === "/" ? [] : routePath.slice(1).split("/");
    const segments = rawSegments.map((segment) => titleCaseSegment(decodeURIComponent(segment)));

    breadcrumbEl.innerHTML = "";
    if (rawSegments.length === 0) {
      breadcrumbEl.style.display = "none";
      return;
    }
    breadcrumbEl.style.display = "flex";

    const homeLink = document.createElement("a");
    homeLink.href = "/";
    homeLink.textContent = "Home";
    breadcrumbEl.appendChild(homeLink);

    let cumulativePath = "";
    for (let i = 0; i < rawSegments.length; i += 1) {
      const separator = document.createElement("span");
      separator.className = "breadcrumb-sep";
      separator.textContent = "/";
      breadcrumbEl.appendChild(separator);

      cumulativePath += "/" + rawSegments[i];
      const segmentLabel = segments[i];
      if (i === rawSegments.length - 1) {
        const current = document.createElement("span");
        current.textContent = segmentLabel;
        breadcrumbEl.appendChild(current);
      } else {
        const link = document.createElement("a");
        link.href = cumulativePath;
        link.textContent = segmentLabel;
        breadcrumbEl.appendChild(link);
      }
    }
  }

  function routePathForDoc(relativePath) {
    if (relativePath === "collaborators.md") {
      return "/";
    }

    let routeValue = relativePath;
    if (routeValue.endsWith("/README.md")) {
      routeValue = routeValue.slice(0, -"/README.md".length);
    } else {
      routeValue = routeValue.replace(/\.md$/i, "");
    }

    return "/" + routeValue
      .split("/")
      .filter((segment) => segment.length > 0)
      .map((segment) => encodeURIComponent(segment))
      .join("/");
  }

  function joinUrlPath(base, child) {
    const normalizedBase = base.endsWith("/") ? base : base + "/";
    const cleanedChild = child.replace(/^\/+/, "");
    return normalizedBase + cleanedChild;
  }

  function encodePath(path) {
    return path
      .split("/")
      .filter((segment) => segment.length > 0)
      .map((segment) => encodeURIComponent(segment))
      .join("/");
  }

  async function fetchDirectoryListing(directoryPath) {
    const encoded = "/" + encodePath(directoryPath) + "/";
    const response = await fetch(encoded + "?ts=" + Date.now(), { cache: "no-store" });
    if (!response.ok) {
      throw new Error("HTTP " + response.status + " at " + encoded);
    }
    const json = await response.json();
    if (!Array.isArray(json)) {
      throw new Error("Unexpected listing response at " + encoded);
    }
    return json;
  }

  async function collectMarkdownPaths(directoryPath = "docs", prefix = "") {
    const entries = await fetchDirectoryListing(directoryPath);
    const files = [];

    for (const entry of entries) {
      const name = (entry && entry.name ? String(entry.name) : "").trim();
      if (!name || name === "../") {
        continue;
      }

      const isDirectory = entry.type === "directory" || name.endsWith("/");
      const cleanName = isDirectory ? name.replace(/\/+$/, "") : name;
      if (!cleanName) {
        continue;
      }

      if (isDirectory) {
        if (cleanName === "assets") {
          continue;
        }
        const nestedDirectory = joinUrlPath(directoryPath, cleanName);
        const nestedPrefix = prefix ? prefix + "/" + cleanName : cleanName;
        const nestedFiles = await collectMarkdownPaths(nestedDirectory, nestedPrefix);
        files.push(...nestedFiles);
        continue;
      }

      if (cleanName.toLowerCase().endsWith(".md")) {
        const relativePath = prefix ? prefix + "/" + cleanName : cleanName;
        files.push(relativePath);
      }
    }

    return files;
  }

  function buildDocsTree(paths) {
    const root = { dirs: new Map(), files: [] };

    for (const relativePath of paths) {
      const segments = relativePath.split("/");
      const fileName = segments[segments.length - 1];
      let node = root;
      let basePath = "";

      for (let i = 0; i < segments.length - 1; i += 1) {
        const segment = segments[i];
        if (!node.dirs.has(segment)) {
          node.dirs.set(segment, { dirs: new Map(), files: [], path: basePath ? basePath + "/" + segment : segment });
        }
        node = node.dirs.get(segment);
        basePath = node.path;
      }

      const filePath = basePath ? basePath + "/" + fileName : fileName;
      node.files.push({ name: fileName, path: filePath });
    }

    return root;
  }

  function renderDocsTreeNode(node, parentPath = "") {
    const list = document.createElement("ul");

    const sortedDirs = Array.from(node.dirs.entries()).sort((a, b) => a[0].localeCompare(b[0]));
    for (const [dirName, dirNode] of sortedDirs) {
      const item = document.createElement("li");
      const details = document.createElement("details");
      const summary = document.createElement("summary");
      const segmentPath = parentPath ? parentPath + "/" + dirName : dirName;

      summary.textContent = titleCaseSegment(dirName);
      details.appendChild(summary);
      details.open = openTreePaths.has(segmentPath);
      details.addEventListener("toggle", () => {
        updateOpenTreePath(segmentPath, details.open);
      });

      details.appendChild(renderDocsTreeNode(dirNode, segmentPath));
      item.appendChild(details);
      list.appendChild(item);
    }

    const sortedFiles = node.files.slice().sort((a, b) => a.name.localeCompare(b.name));
    for (const file of sortedFiles) {
      const item = document.createElement("li");
      const link = document.createElement("a");
      const routePath = routePathForDoc(file.path);
      const label = file.path === "collaborators.md" ? "Home" : titleCaseSegment(file.name);

      link.href = routePath;
      link.textContent = label;
      if (file.path === currentRelativeDocPath) {
        link.className = "active";
      }

      item.appendChild(link);
      list.appendChild(item);
    }

    return list;
  }

  function setupVideoLightboxes() {
    const openButtons = documentEl.querySelectorAll("[data-video-lightbox-open]");
    const closeButtons = documentEl.querySelectorAll("[data-video-lightbox-close]");

    for (const button of openButtons) {
      if (button.dataset.boundOpen === "true") {
        continue;
      }
      button.dataset.boundOpen = "true";
      button.addEventListener("click", () => {
        const targetId = button.getAttribute("data-video-lightbox-open");
        if (!targetId) {
          return;
        }
        const lightbox = documentEl.querySelector("#" + CSS.escape(targetId));
        if (!lightbox) {
          return;
        }
        const frame = lightbox.querySelector("iframe[data-video-embed-src]");
        if (frame && !frame.getAttribute("src")) {
          frame.setAttribute("src", frame.getAttribute("data-video-embed-src") || "");
        }
        lightbox.classList.add("is-open");
        lightbox.setAttribute("aria-hidden", "false");
      });
    }

    for (const button of closeButtons) {
      if (button.dataset.boundClose === "true") {
        continue;
      }
      button.dataset.boundClose = "true";
      button.addEventListener("click", () => {
        const lightbox = button.closest(".video-lightbox");
        if (!lightbox) {
          return;
        }
        lightbox.classList.remove("is-open");
        lightbox.setAttribute("aria-hidden", "true");
        const frame = lightbox.querySelector("iframe[data-video-embed-src]");
        if (frame) {
          frame.removeAttribute("src");
        }
      });
    }

    const lightboxes = documentEl.querySelectorAll(".video-lightbox");
    for (const lightbox of lightboxes) {
      if (lightbox.dataset.boundBackdrop === "true") {
        continue;
      }
      lightbox.dataset.boundBackdrop = "true";
      lightbox.addEventListener("click", (event) => {
        if (event.target !== lightbox) {
          return;
        }
        lightbox.classList.remove("is-open");
        lightbox.setAttribute("aria-hidden", "true");
        const frame = lightbox.querySelector("iframe[data-video-embed-src]");
        if (frame) {
          frame.removeAttribute("src");
        }
      });
    }
  }

  async function loadDocsTree() {
    if (!isHomepage) {
      docsSidebarEl.style.display = "none";
      return;
    }

    try {
      const paths = await collectMarkdownPaths("docs");
      paths.sort((a, b) => a.localeCompare(b));

      const tree = buildDocsTree(paths);
      docsTreeEl.innerHTML = "";
      docsTreeEl.appendChild(renderDocsTreeNode(tree));
    } catch (error) {
      docsTreeEl.innerHTML = "";
      const message = document.createElement("p");
      message.className = "docs-tree-empty";
      message.textContent = "Unable to load docs tree (" + error.message + ")";
      docsTreeEl.appendChild(message);
    }
  }

  async function loadDoc() {
    try {
      const response = await fetch(resolvedDocPath + "?ts=" + Date.now(), { cache: "no-store" });
      if (!response.ok) {
        throw new Error("HTTP " + response.status);
      }
      const text = await response.text();
      if (text !== lastText) {
        documentEl.innerHTML = markdown.render(stripFrontMatter(text));
        setupVideoLightboxes();
        lastText = text;
      }
    } catch (error) {
      const message = "Unable to load " + resolvedDocPath + " (" + error.message + ")";
      if (breadcrumbEl.style.display !== "none") {
        breadcrumbEl.textContent = message;
      }
      documentEl.textContent = message;
    }
  }

  renderBreadcrumb(window.location.pathname);
  loadDocsTree();
  loadDoc();
  setInterval(loadDoc, 1500);
  setInterval(loadDocsTree, 10000);
})();
