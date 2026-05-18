const betaDownloadUrl =
  "https://github.com/lorenjohnson/Hypnograph/releases/download/v0.2.0-beta.12/Hypnograph-0.2.0-12-macOS-unsigned.dmg";

export function HomePage() {
  return (
    <main className="home-page">
      <header className="home-topbar">
        <nav className="home-nav" aria-label="Primary">
          <a href="/docs/user-manual/installation">Documentation</a>
          <a href="/docs/queue">Development</a>
          <a
            className="home-nav-icon"
            href="https://github.com/lorenjohnson/Hypnograph"
            target="_blank"
            rel="noreferrer"
            aria-label="GitHub"
          >
            <svg
              aria-hidden="true"
              viewBox="0 0 24 24"
              fill="currentColor"
            >
              <path d="M12 2C6.48 2 2 6.58 2 12.25c0 4.53 2.87 8.37 6.84 9.73.5.1.68-.22.68-.49 0-.24-.01-1.04-.01-1.89-2.78.62-3.37-1.22-3.37-1.22-.45-1.18-1.11-1.49-1.11-1.49-.91-.64.07-.63.07-.63 1 .07 1.53 1.06 1.53 1.06.9 1.57 2.36 1.12 2.94.86.09-.67.35-1.12.64-1.38-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05A9.35 9.35 0 0 1 12 6.99c.85 0 1.7.12 2.5.35 1.9-1.33 2.74-1.05 2.74-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.8-4.57 5.05.36.32.68.95.68 1.92 0 1.38-.01 2.49-.01 2.83 0 .27.18.59.69.49A10.08 10.08 0 0 0 22 12.25C22 6.58 17.52 2 12 2Z" />
            </svg>
          </a>
        </nav>
      </header>

      <section className="home-hero" aria-labelledby="home-title">
        <div className="home-hero-copy">
          <div className="home-title-lockup">
            <img src="/assets/hypnograph-icon.png" alt="" />
            <h1 id="home-title">Hypnograph</h1>
          </div>
          <p className="home-kicker">Memory-forward visual instrument for macOS</p>
          <p className="home-lede">
            A dream machine for replaying, steering, composing, and performing
            with your own photo and video archive.
          </p>
        </div>

        <aside className="home-download-panel" aria-label="Current beta download">
          <a className="home-download" href={betaDownloadUrl}>
            <svg
              aria-hidden="true"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
              <path d="M7 10l5 5 5-5" />
              <path d="M12 15V3" />
            </svg>
            Download Beta v0.2.0
          </a>
          <p className="home-download-meta">
            <span>Beta</span>
            <span>build 12</span>
            <span>Apple Silicon</span>
          </p>
          <p className="home-download-release">Released May 18, 2026</p>
          <p className="home-download-note">
            There are a couple of extra steps to running the unsigned beta app.
            See the <a href="/docs/user-manual/installation">beta install steps</a>.
          </p>
        </aside>
      </section>

      {/* Demo video is temporarily hidden until the recording is current again.
      <section className="home-video" aria-label="Hypnograph demo video">
        <iframe
          title="Hypnograph demo video"
          src="https://iframe.videodelivery.net/741c294e44de4589ea5e1761601db44a?controls=true"
          allow="accelerometer; gyroscope; autoplay; encrypted-media; picture-in-picture"
          allowFullScreen
          loading="lazy"
        />
      </section>
      */}

      <section className="home-content" aria-labelledby="dream-machine-title">
        <h2 id="dream-machine-title">A Dream Machine</h2>
        <p>
          Instead of browsing your archive like a filing cabinet, Hypnograph
          replays your photos and videos as evolving, remixable sequences. It
          can begin in a generative mode where surprising combinations emerge
          quickly, and it can also be steered into deliberate composition
          through clip selection, timing, layering, blend modes, and effect
          chains.
        </p>
        <p>
          The point is not synthetic generation. The point is to re-encounter
          material that already belongs to your life or project and shape it
          into something that feels newly alive, exploratory, and creatively useful.
          You can follow that process all the way into making whole movies, in a
          way that feels familiar enough to sit down with and playful enough to
          keep discovering.
        </p>
      </section>

      <section className="home-content" aria-labelledby="feedback-title">
        <h2 id="feedback-title">Feedback</h2>
        <p>
          If you download Hypnograph and spend any real time with it, I would
          genuinely love to hear about your experience. Thoughtful user feedback
          has a direct impact on the shape of the product.
        </p>
      </section>

      <section className="home-content" aria-labelledby="development-title">
        <h2 id="development-title">Development</h2>
        <p>
          Hypnograph is being built in public, and you can follow the active
          product development of Hypnograph in the{" "}
          <a href="/docs/queue">Open Product Development Documents</a>.
        </p>
        <p>
          I welcome product-level feedback and discussion, and code-level
          contributions from anyone interested enough to bring either. I do
          anticipate eventually open sourcing Hypnograph, but I have not yet
          settled on a particular license, so for now the project should be
          considered source-available rather than open source. The source code
          for Hypnograph is publicly available on{" "}
          <a href="https://github.com/lorenjohnson/Hypnograph">GitHub</a>.
        </p>
      </section>

      <footer className="home-footer">
        <p>
          Loren Johnson /{" "}
          <a href="mailto:lorenjohnson@gmail.com">lorenjohnson@gmail.com</a> /{" "}
          <a href="https://lorenjohnson.me">lorenjohnson.me</a> /{" "}
          <a href="https://lorenjohnson.dev">lorenjohnson.dev</a>
        </p>
      </footer>
    </main>
  );
}
