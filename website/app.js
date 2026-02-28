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

  inviteForm.addEventListener("submit", () => {
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
        "Submitting... if the confirmation page does not load, email lorenjohnson@gmail.com.";
    }
  });
}

const cinemaIntro = document.querySelector(".cinema-intro");

if (cinemaIntro) {
  const captionWrap = document.querySelector(".cinema-caption-wrap");
  const headlineNode = document.getElementById("cinema-headline");
  const captionNode = document.getElementById("cinema-caption");
  const countNode = document.getElementById("cinema-count");

  const playToggle = document.getElementById("cinema-toggle-play");
  const muteToggle = document.getElementById("cinema-toggle-mute");
  const voiceToggle = document.getElementById("cinema-toggle-voice");
  const enterButton = document.getElementById("cinema-enter");

  const videoStack = document.getElementById("cinema-video-stack");
  const iframeFallback = document.getElementById("cinema-iframe-fallback");
  const primaryVideo = document.getElementById("cinema-video-a");
  const secondaryVideo = document.getElementById("cinema-video-b");

  const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");

  // Drop lightweight MP4 clips in assets/montages and list them here.
  const montageSources = [
    // "assets/montages/hypnograph-intro-01.mp4",
    // "assets/montages/hypnograph-intro-02.mp4",
    // "assets/montages/hypnograph-intro-03.mp4",
    // "assets/montages/hypnograph-intro-04.mp4"
  ];

  const voiceoverSources = [
    // "assets/voiceover/hypnograph-intro-voiceover.mp3"
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
  let introIsPlaying = !reducedMotionQuery.matches;
  let introIsMuted = true;
  let localMontageMode = false;
  let localMontageSources = [];
  let clipCursor = 0;
  let voiceoverEnabled = false;
  let voiceoverReady = false;
  const sceneDurationMs = reducedMotionQuery.matches ? 12000 : 6500;
  const voiceoverAudio = typeof Audio === "function" ? new Audio() : null;

  if (voiceoverAudio) {
    voiceoverAudio.preload = "metadata";
    voiceoverAudio.loop = true;
  }

  function renderScene(index, immediate = false) {
    const scene = scriptScenes[index];
    if (!scene || !headlineNode || !captionNode || !countNode) return;

    if (!immediate && captionWrap) {
      captionWrap.classList.add("is-swapping");
      window.setTimeout(() => {
        headlineNode.textContent = scene.headline;
        captionNode.textContent = scene.caption;
        countNode.textContent = `Scene ${index + 1} / ${scriptScenes.length}`;
        captionWrap.classList.remove("is-swapping");
      }, 150);
      return;
    }

    headlineNode.textContent = scene.headline;
    captionNode.textContent = scene.caption;
    countNode.textContent = `Scene ${index + 1} / ${scriptScenes.length}`;
  }

  function advanceScene() {
    sceneIndex = (sceneIndex + 1) % scriptScenes.length;
    renderScene(sceneIndex);
  }

  function stopSceneLoop() {
    if (sceneTimerId) {
      window.clearInterval(sceneTimerId);
      sceneTimerId = null;
    }
  }

  function startSceneLoop() {
    stopSceneLoop();
    if (!introIsPlaying) return;
    sceneTimerId = window.setInterval(advanceScene, sceneDurationMs);
  }

  function updatePlayButton() {
    if (!playToggle) return;
    playToggle.textContent = introIsPlaying ? "Pause" : "Play";
  }

  function updateMuteButton() {
    if (!muteToggle) return;
    if (!localMontageMode) {
      muteToggle.disabled = true;
      muteToggle.textContent = "Muted";
      return;
    }

    muteToggle.disabled = false;
    muteToggle.textContent = introIsMuted ? "Unmute" : "Mute";
  }

  function updateVoiceButton() {
    if (!voiceToggle) return;
    if (!voiceoverReady) {
      voiceToggle.disabled = true;
      voiceToggle.textContent = "Voiceover Soon";
      return;
    }

    voiceToggle.disabled = false;
    voiceToggle.textContent = voiceoverEnabled ? "Voice Off" : "Voice On";
  }

  function applyMuteState() {
    if (primaryVideo) primaryVideo.muted = introIsMuted;
    if (secondaryVideo) secondaryVideo.muted = introIsMuted;
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

  async function findLocalMontages() {
    const checks = await Promise.all(
      montageSources.map(async (path) => ((await sourceExists(path)) ? path : null))
    );
    return checks.filter(Boolean);
  }

  async function findVoiceoverTrack() {
    const checks = await Promise.all(
      voiceoverSources.map(async (path) => ((await sourceExists(path)) ? path : null))
    );
    return checks.find(Boolean) || null;
  }

  function syncVoiceoverPlayback() {
    if (!voiceoverReady || !voiceoverAudio) return;

    if (!voiceoverEnabled || !introIsPlaying) {
      voiceoverAudio.pause();
      return;
    }

    voiceoverAudio.play().catch(() => {
      voiceoverEnabled = false;
      updateVoiceButton();
    });
  }

  async function setupVoiceover() {
    if (!voiceoverAudio || voiceoverSources.length === 0) {
      updateVoiceButton();
      return;
    }

    const track = await findVoiceoverTrack();
    if (!track) {
      updateVoiceButton();
      return;
    }

    voiceoverAudio.src = track;
    voiceoverReady = true;
    updateVoiceButton();
  }

  function fallbackToHostedPlayback() {
    localMontageMode = false;
    if (videoStack) videoStack.hidden = true;
    if (iframeFallback) iframeFallback.hidden = false;
    updateMuteButton();
  }

  function playNextClip() {
    if (!localMontageMode || !primaryVideo || localMontageSources.length === 0) return;

    primaryVideo.src = localMontageSources[clipCursor];
    primaryVideo.load();
    clipCursor = (clipCursor + 1) % localMontageSources.length;

    if (!introIsPlaying) return;
    primaryVideo.play().catch(() => {
      fallbackToHostedPlayback();
    });
  }

  async function setupLocalMontage() {
    if (!primaryVideo || !videoStack) return;

    localMontageSources = await findLocalMontages();
    if (localMontageSources.length === 0) {
      fallbackToHostedPlayback();
      return;
    }

    localMontageMode = true;
    videoStack.hidden = false;
    if (iframeFallback) iframeFallback.hidden = true;
    if (secondaryVideo) secondaryVideo.hidden = true;

    applyMuteState();
    playNextClip();

    primaryVideo.addEventListener("ended", () => {
      playNextClip();
    });

    primaryVideo.addEventListener("error", () => {
      fallbackToHostedPlayback();
    });
  }

  function togglePlayback() {
    introIsPlaying = !introIsPlaying;
    updatePlayButton();

    if (introIsPlaying) {
      startSceneLoop();
      if (localMontageMode && primaryVideo) {
        primaryVideo.play().catch(() => {
          fallbackToHostedPlayback();
        });
      }
      syncVoiceoverPlayback();
      return;
    }

    stopSceneLoop();
    if (localMontageMode && primaryVideo) primaryVideo.pause();
    syncVoiceoverPlayback();
  }

  function toggleMute() {
    if (!localMontageMode) return;
    introIsMuted = !introIsMuted;
    applyMuteState();
  }

  function toggleVoiceover() {
    if (!voiceoverReady) return;
    voiceoverEnabled = !voiceoverEnabled;
    updateVoiceButton();
    syncVoiceoverPlayback();
  }

  function scrollToManifesto() {
    const manifesto = document.getElementById("about");
    if (!manifesto) return;
    manifesto.scrollIntoView({
      behavior: reducedMotionQuery.matches ? "auto" : "smooth",
      block: "start"
    });
  }

  if (playToggle) playToggle.addEventListener("click", togglePlayback);
  if (muteToggle) muteToggle.addEventListener("click", toggleMute);
  if (voiceToggle) voiceToggle.addEventListener("click", toggleVoiceover);
  if (enterButton) enterButton.addEventListener("click", scrollToManifesto);

  const handleReducedMotionChange = (event) => {
    if (!event.matches) return;
    introIsPlaying = false;
    updatePlayButton();
    stopSceneLoop();
    if (localMontageMode && primaryVideo) primaryVideo.pause();
    syncVoiceoverPlayback();
  };

  if (typeof reducedMotionQuery.addEventListener === "function") {
    reducedMotionQuery.addEventListener("change", handleReducedMotionChange);
  } else if (typeof reducedMotionQuery.addListener === "function") {
    reducedMotionQuery.addListener(handleReducedMotionChange);
  }

  renderScene(sceneIndex, true);
  updatePlayButton();
  updateMuteButton();
  updateVoiceButton();
  startSceneLoop();
  setupLocalMontage();
  setupVoiceover();
}
