import fs from "node:fs";
import path from "node:path";

const websiteDir = path.resolve(import.meta.dirname, "..");
const repoRoot = path.resolve(websiteDir, "..");
const docsDir = path.join(repoRoot, "docs");
const pagesDir = path.join(websiteDir, ".holocron-pages");
const generatedDocsDir = path.join(pagesDir, "docs");
const configPath = path.join(websiteDir, "docs.json");
function normalizeMarkdownForMdx(content) {
  return content.replace(/<((?:https?:\/\/|mailto:)[^>\s]+)>/g, "[$1]($1)");
}

function copyForHolocron(source, destination) {
  const stat = fs.statSync(source);
  if (stat.isDirectory()) {
    fs.mkdirSync(destination, { recursive: true });
    for (const entry of fs.readdirSync(source)) {
      if (entry.startsWith(".")) {
        continue;
      }
      copyForHolocron(path.join(source, entry), path.join(destination, entry));
    }
    return;
  }

  fs.mkdirSync(path.dirname(destination), { recursive: true });
  if (source.toLowerCase().endsWith(".md")) {
    const content = fs.readFileSync(source, "utf8");
    fs.writeFileSync(destination, normalizeMarkdownForMdx(content));
    return;
  }

  fs.copyFileSync(source, destination);
}

function titleCaseSegment(segment) {
  return segment
    .replace(/\.md$/i, "")
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function slugForMarkdown(absPath) {
  return `docs/${path
    .relative(docsDir, absPath)
    .replace(/\\/g, "/")
    .replace(/\.md$/i, "")}`;
}

function buildDocsGroup(absDir) {
  const entries = fs
    .readdirSync(absDir, { withFileTypes: true })
    .filter((entry) => !entry.name.startsWith("."))
    .sort((a, b) => {
      if (a.isDirectory() !== b.isDirectory()) {
        return a.isDirectory() ? -1 : 1;
      }
      return a.name.localeCompare(b.name);
    });

  const pages = [];
  for (const entry of entries) {
    const absPath = path.join(absDir, entry.name);
    if (entry.isDirectory()) {
      const child = buildDocsGroup(absPath);
      if (child.pages.length > 0) {
        pages.push(child);
      }
      continue;
    }

    if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) {
      pages.push(slugForMarkdown(absPath));
    }
  }

  return {
    group: titleCaseSegment(path.basename(absDir)),
    expanded: absDir === docsDir,
    pages,
  };
}

function withoutEntries(entries, excluded) {
  return entries.filter((entry) => {
    if (typeof entry === "string") {
      return !excluded.has(entry);
    }

    return !excluded.has(entry.group);
  });
}

fs.rmSync(pagesDir, { force: true, recursive: true });
fs.mkdirSync(pagesDir, { recursive: true });
copyForHolocron(docsDir, generatedDocsDir);

const docsGroup = buildDocsGroup(docsDir);
const userManualGroup = buildDocsGroup(path.join(docsDir, "user-manual"));
const installationSlug = "docs/user-manual/installation";
const controlsSlug = "docs/user-manual/controls";
const glossarySlug = "docs/user-manual/glossary";
const userManualPages = [
  installationSlug,
  controlsSlug,
  ...userManualGroup.pages.filter(
    (page) =>
      page !== "docs/user-manual/index" &&
      page !== installationSlug &&
      page !== controlsSlug &&
      page !== glossarySlug,
  ),
  glossarySlug,
];

const developmentPages = withoutEntries(
  docsGroup.pages,
  new Set(["User Manual", "Documentation", "docs/queue"]),
);

const config = {
  $schema: "https://unpkg.com/@holocron.so/vite/src/schema.json",
  name: "Hypnograph",
  description:
    "Hypnograph is a memory-forward visual instrument for macOS, built in public through open product development documents.",
  logo: {
    light: "/assets/hypnograph-icon.png",
    href: "/",
    text: "Hypnograph",
  },
  favicon: "/assets/hypnograph-icon.png",
  colors: {
    primary: "#3e9fff",
  },
  icons: {
    library: "lucide",
  },
  appearance: {
    default: "dark",
  },
  assistant: {
    enabled: false,
  },
  decorativeLines: "none",
  navbar: {
    links: [
      {
        type: "github",
        href: "https://github.com/lorenjohnson/Hypnograph",
      },
    ],
  },
  navigation: {
    tabs: [
      {
        tab: "Documentation",
        pages: userManualPages,
      },
      {
        tab: "Development",
        pages: ["docs/queue", ...developmentPages],
      },
    ],
  },
  redirects: [
    {
      source: "/docs",
      destination: "/docs/queue",
    },
    {
      source: "/docs/user-manual",
      destination: "/docs/user-manual/installation",
    },
  ],
};

fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
console.log(`Generated ${path.relative(repoRoot, configPath)} with ${docsGroup.pages.length} top-level docs entries.`);
