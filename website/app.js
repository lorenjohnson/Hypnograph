if (typeof window !== "undefined" && window.location?.pathname) {
  const path = window.location.pathname;
  if (/home\.html$/i.test(path)) {
    const rootPath = path.replace(/home\.html$/i, "") || "/";
    const target = `${rootPath}${window.location.search || ""}${window.location.hash || ""}`;
    if (target !== `${path}${window.location.search || ""}${window.location.hash || ""}`) {
      window.history.replaceState({}, "", target);
    }
  }
}

const sections = document.querySelectorAll(".section-reveal");
const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.15 }
);

sections.forEach((section) => observer.observe(section));

const inviteForm = document.getElementById("beta-invite-form");
const inviteNote = document.getElementById("beta-invite-note");

if (inviteForm) {
  const submitButton = inviteForm.querySelector('button[type="submit"]');
  const nextField = inviteForm.querySelector('input[name="_next"]');
  let isSubmitting = false;

  inviteForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (isSubmitting) return;
    isSubmitting = true;

    if (nextField && window.location?.origin) {
      const origin = window.location.origin;
      if (origin.startsWith("http://localhost") || origin.startsWith("http://127.0.0.1")) {
        nextField.value = `${origin}/thank-you.html`;
      }
    }

    if (submitButton) {
      submitButton.disabled = true;
      submitButton.textContent = "Sending...";
    }

    if (inviteNote) {
      inviteNote.textContent =
        "Submitting...";
    }

    const action = inviteForm.getAttribute("action") || "https://formsubmit.co/lorenjohnson@gmail.com";
    const ajaxAction =
      action.includes("formsubmit.co/") && !action.includes("/ajax/")
        ? action.replace("formsubmit.co/", "formsubmit.co/ajax/")
        : action;
    const formData = new FormData(inviteForm);

    try {
      const response = await fetch(ajaxAction, {
        method: "POST",
        body: formData,
        headers: {
          Accept: "application/json"
        }
      });

      if (!response.ok) throw new Error(`Submission failed (${response.status})`);

      const nextUrl = nextField?.value || "thank-you.html";
      window.location.assign(nextUrl);
    } catch {
      isSubmitting = false;
      if (submitButton) {
        submitButton.disabled = false;
        submitButton.textContent = "Request Invite";
      }
      if (inviteNote) {
        inviteNote.textContent =
          "Could not submit right now. Please try again, or email lorenjohnson@gmail.com.";
      }
    }
  });
}

const cinemaIntro = document.querySelector(".cinema-intro");

if (cinemaIntro) {
  const mediaShell = document.querySelector(".cinema-media-shell");
  const captionWrap = document.querySelector(".cinema-caption-wrap");
  const headlineNode = document.getElementById("cinema-headline");
  const captionNode = document.getElementById("cinema-caption");
  const finalSceneCta = document.getElementById("cinema-final-cta");
  const prevSceneButton = document.getElementById("cinema-scene-prev");

  const playToggle = document.getElementById("cinema-toggle-play");
  const nextSceneButton = document.getElementById("cinema-scene-next");
  const muteToggle = document.getElementById("cinema-toggle-mute");

  const videoStack = document.getElementById("cinema-video-stack");
  const iframeFallback = document.getElementById("cinema-iframe-fallback");
  const hostedIframe = document.getElementById("cinema-hosted-iframe");
  const primaryVideo = document.getElementById("cinema-video-a");
  const countdownOverlay = document.getElementById("cinema-countdown");
  const countdownValue = document.getElementById("cinema-countdown-value");

  const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  const defaultCinemaAspectRatio = 1920 / 1242;
  const hostedStreamManifestSource =
    "https://videodelivery.net/6948b43abd96d022bccc2228064ceecd/manifest/video.m3u8";
  const countdownFrames = ["3", "2", "1"];

  // Fallback rotating clips (used when per-scene clips are not configured).
  const montagePlaylistSources = [
    // "assets/montages/hypnograph-intro-01.mp4",
    // "assets/montages/hypnograph-intro-02.mp4",
    // "assets/montages/hypnograph-intro-03.mp4",
    // "assets/montages/hypnograph-intro-04.mp4"
  ];

  // Scene-linked clips. When this has one valid file per scene, scenes and video stay locked together.
  const sceneClipSources = [
    // "assets/montages/scene-01.mp4",
    // "assets/montages/scene-02.mp4",
    // "assets/montages/scene-03.mp4",
    // "assets/montages/scene-04.mp4",
    // "assets/montages/scene-05.mp4",
    // "assets/montages/scene-06.mp4",
    // "assets/montages/scene-07.mp4",
    // "assets/montages/scene-08.mp4"
  ];

  const scriptScenes = [
    {
      headline: "Your archive, alive.",
      caption:
        "How many hours have you spent migrating phones and laptops to keep your past from disappearing?"
    },
    {
      headline: "Digital memory is absolute until it is gone.",
      caption:
        "A photo can stay perfect for ten years, then vanish in a single sync error. All there, or nothing."
    },
    {
      headline: "Physical photos age with you.",
      caption:
        "A curled print from 1942 feels alive because time touched it. Your files did not."
    },
    {
      headline: "You want encounter, not a catalog.",
      caption:
        "No one wants to search 37,000 clips just to find one look from their father."
    },
    {
      headline: "Not a fake highlight reel.",
      caption:
        "Not a polished life movie. Not romantic glaze. A raw stream with friction, delight, and surprise."
    },
    {
      headline: "Open it like a late-night channel.",
      caption:
        "Exes, mountains, dance floors, strange fragments. Let the cuts collide and tell the truth."
    },
    {
      headline: "Catch moments and keep moving.",
      caption:
        "Rewind, favorite, remove, export. Hold onto what hits and let the rest pass through."
    },
    {
      headline: "Hypnograph.",
      caption:
        "Looking back with surprise. Rebuilding the present from ashes, fragments, and your own footage."
    }
  ];

  let sceneIndex = 0;
  let sceneTimerId = null;
  let introIsPlaying = false;
  let introIsMuted = true;
  let hasShowStarted = false;
  let mediaMode = "hosted";
  let playlistSources = [];
  let sceneSources = [];
  let clipCursor = 0;
  let activeVideoSource = "";
  const sceneDurationMs = reducedMotionQuery.matches ? 12000 : 6500;
  const iconMarkup = {
    play:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M8 5v14l11-7z"></path></svg>',
    pause:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M7 5h3v14H7zm7 0h3v14h-3z"></path></svg>',
    muted:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M14 5v14l-6-4H4V9h4zm4.59 2L20 8.41 17.41 11 20 13.59 18.59 15 16 12.41 13.41 15 12 13.59 14.59 11 12 8.41 13.41 7 16 9.59z"></path></svg>',
    volume:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M14 5v14l-6-4H4V9h4z"></path><path d="M16.5 8.5a4.5 4.5 0 0 1 0 7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"></path></svg>'
  };

  function setIconButton(button, icon, label) {
    if (!button) return;
    const markup = iconMarkup[icon] || "";
    button.innerHTML = `${markup}<span class="sr-only">${label}</span>`;
    button.setAttribute("aria-label", label);
    button.setAttribute("title", label);
  }

  function setCinemaAspectRatio(ratio) {
    if (!mediaShell || !Number.isFinite(ratio) || ratio <= 0) return;
    mediaShell.style.setProperty("--cinema-media-ratio", String(ratio));
  }

  function ensureHostedIframeLoaded() {
    if (!hostedIframe) return;
    if (hostedIframe.getAttribute("src")) return;
    const deferredSrc = hostedIframe.dataset.src;
    if (deferredSrc) hostedIframe.setAttribute("src", deferredSrc);
  }

  function isSceneSyncedMode() {
    return mediaMode === "scene";
  }

  function hasLocalVideoMode() {
    return mediaMode === "scene" || mediaMode === "playlist";
  }

  function shouldUseTimedSceneLoop() {
    return introIsPlaying && !isSceneSyncedMode();
  }

  function updateHostedFreezeVisual() {
    if (!mediaShell) return;
    // Hosted iframe playback cannot be paused reliably across browsers, so keep it visible.
    mediaShell.classList.remove("is-frozen");
  }

  function setLocalPlaybackVisibility(isLocalPlaybackVisible) {
    if (videoStack) videoStack.hidden = !isLocalPlaybackVisible;
    if (primaryVideo) primaryVideo.classList.toggle("is-active", isLocalPlaybackVisible);
    if (iframeFallback) iframeFallback.hidden = isLocalPlaybackVisible ? true : !hasShowStarted;
  }

  function updateSceneNavigationState() {
    const hasMultipleScenes = scriptScenes.length > 1;
    if (prevSceneButton) prevSceneButton.disabled = !hasMultipleScenes || sceneIndex <= 0;
    if (nextSceneButton) nextSceneButton.disabled = !hasMultipleScenes || sceneIndex >= scriptScenes.length - 1;
  }

  function updateFinalSceneCta() {
    if (!finalSceneCta) return;
    finalSceneCta.hidden = sceneIndex !== scriptScenes.length - 1;
  }

  function playVideoSource(source) {
    if (!primaryVideo || !source) return;
    setLocalPlaybackVisibility(true);

    if (activeVideoSource !== source) {
      activeVideoSource = source;
      primaryVideo.src = source;
      primaryVideo.load();
    }

    if (!introIsPlaying) {
      primaryVideo.pause();
      return;
    }

    primaryVideo.play().catch(() => {
      fallbackToHostedPlayback();
    });
  }

  function syncSceneVideo() {
    if (!isSceneSyncedMode()) return;
    const sceneSource = sceneSources[sceneIndex];
    if (!sceneSource) {
      fallbackToHostedPlayback();
      return;
    }
    playVideoSource(sceneSource);
  }

  function beginIntroShow() {
    if (hasShowStarted) return;
    hasShowStarted = true;
    introIsPlaying = true;

    if (!hasLocalVideoMode()) {
      ensureHostedIframeLoaded();
      setLocalPlaybackVisibility(false);
    }

    startSceneLoop();

    if (hasLocalVideoMode()) {
      if (isSceneSyncedMode()) {
        syncSceneVideo();
      } else if (activeVideoSource) {
        playVideoSource(activeVideoSource);
      } else if (playlistSources.length > 0) {
        playVideoSource(playlistSources[clipCursor % playlistSources.length]);
      } else {
        fallbackToHostedPlayback();
      }
    }

    updatePlayButton();
    updateHostedFreezeVisual();
  }

  function runCountdown() {
    if (!countdownOverlay || !countdownValue) return Promise.resolve();

    const stepMs = reducedMotionQuery.matches ? 650 : 900;
    countdownOverlay.hidden = false;
    countdownOverlay.classList.remove("is-finished");

    return new Promise((resolve) => {
      let frameIndex = 0;

      const tick = () => {
        if (frameIndex >= countdownFrames.length) {
          countdownOverlay.classList.add("is-finished");
          window.setTimeout(() => {
            countdownOverlay.hidden = true;
            resolve();
          }, 340);
          return;
        }

        countdownValue.textContent = countdownFrames[frameIndex];
        countdownOverlay.classList.remove("is-ticking");
        void countdownOverlay.offsetWidth;
        countdownOverlay.classList.add("is-ticking");
        frameIndex += 1;
        window.setTimeout(tick, stepMs);
      };

      tick();
    });
  }

  function renderScene(index, immediate = false) {
    const scene = scriptScenes[index];
    if (!scene || !headlineNode || !captionNode) return;

    if (!immediate && captionWrap) {
      captionWrap.classList.add("is-swapping");
      window.setTimeout(() => {
        headlineNode.textContent = scene.headline;
        captionNode.textContent = scene.caption;
        captionWrap.classList.remove("is-swapping");
      }, 150);
      return;
    }

    headlineNode.textContent = scene.headline;
    captionNode.textContent = scene.caption;
  }

  function advanceScene() {
    if (sceneIndex >= scriptScenes.length - 1) {
      updateSceneNavigationState();
      updateFinalSceneCta();
      return false;
    }

    sceneIndex += 1;
    renderScene(sceneIndex);
    updateSceneNavigationState();
    updateFinalSceneCta();
    syncSceneVideo();
    return true;
  }

  function stopSceneLoop() {
    if (sceneTimerId) {
      window.clearTimeout(sceneTimerId);
      sceneTimerId = null;
    }
  }

  function startSceneLoop() {
    stopSceneLoop();
    if (!shouldUseTimedSceneLoop()) return;
    sceneTimerId = window.setTimeout(() => {
      const didAdvance = advanceScene();
      if (!didAdvance) {
        stopSceneLoop();
        return;
      }
      startSceneLoop();
    }, sceneDurationMs);
  }

  function stepScene(step) {
    const nextIndex = Math.min(Math.max(sceneIndex + step, 0), scriptScenes.length - 1);
    if (nextIndex === sceneIndex) return;
    sceneIndex = nextIndex;
    renderScene(sceneIndex);
    updateSceneNavigationState();
    updateFinalSceneCta();
    syncSceneVideo();
    if (shouldUseTimedSceneLoop()) startSceneLoop();
  }

  function updatePlayButton() {
    if (!playToggle) return;
    if (introIsPlaying) {
      setIconButton(playToggle, "pause", "Pause intro");
      return;
    }

    setIconButton(playToggle, "play", "Play intro");
  }

  function updateMuteButton() {
    if (!muteToggle) return;
    if (!hasLocalVideoMode()) {
      muteToggle.disabled = true;
      setIconButton(muteToggle, "muted", "Audio unavailable");
      return;
    }

    muteToggle.disabled = false;
    if (introIsMuted) {
      setIconButton(muteToggle, "muted", "Unmute intro");
      return;
    }

    setIconButton(muteToggle, "volume", "Mute intro");
  }

  function applyMuteState() {
    if (primaryVideo) primaryVideo.muted = introIsMuted;
    updateMuteButton();
  }

  async function sourceExists(path) {
    try {
      const head = await fetch(path, { method: "HEAD", cache: "no-store" });
      if (head.ok || head.status === 405) return true;
      return false;
    } catch {
      return false;
    }
  }

  async function resolveExistingSources(sources) {
    const checks = await Promise.all(
      sources.map(async (path) => ((await sourceExists(path)) ? path : null))
    );
    return checks;
  }

  function fallbackToHostedPlayback() {
    mediaMode = "hosted";
    activeVideoSource = "";
    if (primaryVideo) {
      primaryVideo.pause();
      primaryVideo.loop = false;
    }
    setLocalPlaybackVisibility(false);
    ensureHostedIframeLoaded();
    setCinemaAspectRatio(defaultCinemaAspectRatio);
    updateMuteButton();
    updateHostedFreezeVisual();
  }

  function playNextPlaylistClip() {
    if (mediaMode !== "playlist" || playlistSources.length === 0) return;

    const source = playlistSources[clipCursor % playlistSources.length];
    clipCursor = (clipCursor + 1) % playlistSources.length;
    playVideoSource(source);
  }

  function setupHostedStreamVideoFallback() {
    if (!primaryVideo) return false;
    mediaMode = "playlist";
    playlistSources = [hostedStreamManifestSource];
    clipCursor = 0;
    primaryVideo.loop = true;
    primaryVideo.preload = "auto";
    setLocalPlaybackVisibility(true);
    applyMuteState();
    playVideoSource(hostedStreamManifestSource);
    return true;
  }

  async function setupIntroMediaMode() {
    if (!primaryVideo || !videoStack) return;

    const hasSceneClipConfig = sceneClipSources.length === scriptScenes.length;
    if (hasSceneClipConfig) {
      const resolvedScenes = await resolveExistingSources(sceneClipSources);
      const allSceneSourcesFound = resolvedScenes.every(Boolean);
      if (allSceneSourcesFound) {
        mediaMode = "scene";
        sceneSources = resolvedScenes;
        primaryVideo.loop = false;
        setLocalPlaybackVisibility(true);
        applyMuteState();
        syncSceneVideo();
        return;
      }
    }

    const resolvedPlaylist = await resolveExistingSources(montagePlaylistSources);
    playlistSources = resolvedPlaylist.filter(Boolean);
    if (playlistSources.length > 0) {
      mediaMode = "playlist";
      clipCursor = 0;
      primaryVideo.loop = false;
      setLocalPlaybackVisibility(true);
      applyMuteState();
      playNextPlaylistClip();
      return;
    }

    if (setupHostedStreamVideoFallback()) return;

    fallbackToHostedPlayback();
  }

  function togglePlayback() {
    if (!hasShowStarted) {
      beginIntroShow();
      return;
    }

    introIsPlaying = !introIsPlaying;
    updatePlayButton();
    updateHostedFreezeVisual();

    if (introIsPlaying) {
      startSceneLoop();
      if (hasLocalVideoMode()) {
        if (isSceneSyncedMode()) {
          syncSceneVideo();
        } else if (activeVideoSource) {
          playVideoSource(activeVideoSource);
        } else if (playlistSources.length > 0) {
          playVideoSource(playlistSources[clipCursor % playlistSources.length]);
        } else {
          fallbackToHostedPlayback();
        }
      } else {
        ensureHostedIframeLoaded();
      }
      return;
    }

    stopSceneLoop();
    if (hasLocalVideoMode() && primaryVideo) primaryVideo.pause();
  }

  function toggleMute() {
    if (!hasLocalVideoMode()) return;
    introIsMuted = !introIsMuted;
    applyMuteState();
  }

  function showPreviousScene() {
    stepScene(-1);
  }

  function showNextScene() {
    stepScene(1);
  }

  if (primaryVideo) {
    primaryVideo.addEventListener("loadedmetadata", () => {
      if (primaryVideo.videoWidth && primaryVideo.videoHeight) {
        setCinemaAspectRatio(primaryVideo.videoWidth / primaryVideo.videoHeight);
      }
    });

    primaryVideo.addEventListener("ended", () => {
      if (!introIsPlaying) return;
      if (isSceneSyncedMode()) {
        advanceScene();
        return;
      }
      playNextPlaylistClip();
    });

    primaryVideo.addEventListener("error", () => {
      fallbackToHostedPlayback();
    });
  }

  if (playToggle) playToggle.addEventListener("click", togglePlayback);
  if (prevSceneButton) prevSceneButton.addEventListener("click", showPreviousScene);
  if (nextSceneButton) nextSceneButton.addEventListener("click", showNextScene);
  if (muteToggle) muteToggle.addEventListener("click", toggleMute);

  const handleReducedMotionChange = () => {
    if (!hasShowStarted || !introIsPlaying) return;
    startSceneLoop();
  };

  if (typeof reducedMotionQuery.addEventListener === "function") {
    reducedMotionQuery.addEventListener("change", handleReducedMotionChange);
  } else if (typeof reducedMotionQuery.addListener === "function") {
    reducedMotionQuery.addListener(handleReducedMotionChange);
  }

  renderScene(sceneIndex, true);
  updateSceneNavigationState();
  updateFinalSceneCta();
  setCinemaAspectRatio(defaultCinemaAspectRatio);
  updatePlayButton();
  updateMuteButton();
  updateHostedFreezeVisual();
  ensureHostedIframeLoaded();
  setupIntroMediaMode();
  runCountdown().then(() => {
    beginIntroShow();
  });
}
