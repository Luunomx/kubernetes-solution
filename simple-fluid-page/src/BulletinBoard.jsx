import React, { useEffect, useRef, useState } from "react";
import "./BulletinBoard.css";

const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL || "/api").replace(/\/$/, "");
const DISPLAY_NAME_STORAGE_KEY = "bulletinboard.displayName";
const CLIENT_ID_STORAGE_KEY = "bulletinboard.clientId";
const WS_RECONNECT_DELAY_MS = 2000;
const NAME_COLORS = [
  "#ff7ab2",
  "#ffb86b",
  "#ffe66d",
  "#70e1b5",
  "#67d5ff",
  "#b79cff",
  "#ff8a65",
  "#c4a7ff",
];

function getSavedDisplayName() {
  if (typeof window === "undefined") return "";

  return window.localStorage.getItem(DISPLAY_NAME_STORAGE_KEY) || "";
}

function getNameColor(name) {
  const normalizedName = name.trim().toLowerCase();
  let hash = 0;

  for (let index = 0; index < normalizedName.length; index += 1) {
    hash = (hash * 31 + normalizedName.charCodeAt(index)) | 0;
  }

  return NAME_COLORS[Math.abs(hash) % NAME_COLORS.length];
}

function getClientId() {
  if (typeof window === "undefined") return "server-render";

  const savedClientId = window.sessionStorage.getItem(CLIENT_ID_STORAGE_KEY);
  if (savedClientId) return savedClientId;

  const newClientId =
    window.crypto?.randomUUID?.() ||
    `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  window.sessionStorage.setItem(CLIENT_ID_STORAGE_KEY, newClientId);
  return newClientId;
}

function getWebSocketUrl() {
  const apiUrl = new URL(`${API_BASE_URL}/ws`, window.location.origin);
  apiUrl.protocol = apiUrl.protocol === "https:" ? "wss:" : "ws:";
  return apiUrl.toString();
}

function playNotificationTone(audioContext) {
  const startTime = audioContext.currentTime;
  const oscillator = audioContext.createOscillator();
  const gain = audioContext.createGain();

  oscillator.type = "sine";
  oscillator.frequency.setValueAtTime(880, startTime);
  oscillator.frequency.exponentialRampToValueAtTime(660, startTime + 0.14);

  gain.gain.setValueAtTime(0.0001, startTime);
  gain.gain.exponentialRampToValueAtTime(0.08, startTime + 0.015);
  gain.gain.exponentialRampToValueAtTime(0.0001, startTime + 0.18);

  oscillator.connect(gain);
  gain.connect(audioContext.destination);
  oscillator.start(startTime);
  oscillator.stop(startTime + 0.18);
}

export default function BulletinBoard() {
  const [displayName, setDisplayName] = useState(getSavedDisplayName);
  const [nameDraft, setNameDraft] = useState(getSavedDisplayName);
  const [isNameDialogOpen, setIsNameDialogOpen] = useState(
    () => !getSavedDisplayName(),
  );
  const [message, setMessage] = useState("");
  const [posts, setPosts] = useState([]);
  const [error, setError] = useState("");
  const [nameError, setNameError] = useState("");
  const postsRef = useRef(null);
  const clientIdRef = useRef(getClientId());
  const knownPostIdsRef = useRef(new Set());
  const audioContextRef = useRef(null);

  // ----------------------------
  // Fetch posts from backend
  // ----------------------------
  useEffect(() => {
    const loadPosts = async () => {
      try {
        const res = await fetch(`${API_BASE_URL}/posts`);
        if (!res.ok) throw new Error("Failed to fetch posts");
        const data = await res.json();
        knownPostIdsRef.current = new Set(data.map((post) => post.id));
        setPosts(data);
      } catch (err) {
        console.error("Error fetching posts:", err);
      }
    };
    loadPosts();
  }, []);

  // Unlock the audio context from a user gesture. Mobile browsers require
  // this before they allow a later WebSocket event to play a sound.
  useEffect(() => {
    const unlockAudio = () => {
      const AudioContextConstructor =
        window.AudioContext || window.webkitAudioContext;
      if (!AudioContextConstructor) return;

      if (!audioContextRef.current) {
        audioContextRef.current = new AudioContextConstructor();
      }

      if (audioContextRef.current.state === "suspended") {
        audioContextRef.current.resume().catch(() => {});
      }
    };

    window.addEventListener("pointerdown", unlockAudio, { passive: true });
    window.addEventListener("keydown", unlockAudio);

    return () => {
      window.removeEventListener("pointerdown", unlockAudio);
      window.removeEventListener("keydown", unlockAudio);
    };
  }, []);

  // ----------------------------
  // Listen for live post updates
  // ----------------------------
  useEffect(() => {
    let socket;
    let reconnectTimer;
    let isStopped = false;

    const connect = () => {
      if (isStopped) return;

      socket = new WebSocket(getWebSocketUrl());

      socket.onmessage = (event) => {
        if (typeof event.data !== "string") return;

        try {
          const update = JSON.parse(event.data);

          if (update.type === "chatReset") {
            knownPostIdsRef.current.clear();
            setPosts([]);
            return;
          }

          if (update.type !== "postCreated" || !update.post) return;

          const postId = update.post.id;
          if (knownPostIdsRef.current.has(postId)) return;

          knownPostIdsRef.current.add(postId);
          setPosts((currentPosts) => [...currentPosts, update.post]);

          if (update.clientId !== clientIdRef.current) {
            const audioContext = audioContextRef.current;
            if (audioContext?.state === "running") {
              playNotificationTone(audioContext);
            }
          }
        } catch (err) {
          console.error("Error handling live post update:", err);
        }
      };

      socket.onclose = () => {
        if (!isStopped) {
          reconnectTimer = window.setTimeout(connect, WS_RECONNECT_DELAY_MS);
        }
      };

      socket.onerror = () => socket.close();
    };

    connect();

    return () => {
      isStopped = true;
      window.clearTimeout(reconnectTimer);
      socket?.close();
    };
  }, []);

  useEffect(() => {
    const postsContainer = postsRef.current;
    if (postsContainer) {
      postsContainer.scrollTop = postsContainer.scrollHeight;
    }
  }, [posts]);

  const openNameEditor = () => {
    setNameDraft(displayName);
    setNameError("");
    setIsNameDialogOpen(true);
  };

  const handleNameSubmit = (e) => {
    e.preventDefault();
    const nextName = nameDraft.trim();

    if (!nextName) {
      setNameError("Please choose a name before continuing.");
      return;
    }

    window.localStorage.setItem(DISPLAY_NAME_STORAGE_KEY, nextName);
    setDisplayName(nextName);
    setNameError("");
    setIsNameDialogOpen(false);
  };

  // ----------------------------
  // Handle form submission
  // ----------------------------
  const handleSubmit = async (e) => {
    e.preventDefault();
    setError("");
    if (!displayName) {
      openNameEditor();
      return;
    }

    if (!message.trim()) {
      setError("Please write a message before posting.");
      return;
    }

    try {
      const res = await fetch(`${API_BASE_URL}/posts`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: displayName,
          message: message.trim(),
          clientId: clientIdRef.current,
        }),
      });

      if (!res.ok) throw new Error("Failed to post message");

      setMessage("");

      // Refresh post list
      const updated = await fetch(`${API_BASE_URL}/posts`);
      if (!updated.ok) throw new Error("Failed to refresh posts");
      const updatedPosts = await updated.json();
      knownPostIdsRef.current = new Set(updatedPosts.map((post) => post.id));
      setPosts(updatedPosts);
    } catch (err) {
      console.error("Error submitting post:", err);
      setError("The message could not be posted. Please try again.");
    }
  };

  const handleReset = async () => {
    const confirmed = window.confirm(
      "Reset the chat for everyone? This cannot be undone.",
    );
    if (!confirmed) return;

    setError("");

    try {
      const res = await fetch(`${API_BASE_URL}/posts`, { method: "DELETE" });
      if (!res.ok) throw new Error("Failed to reset chat");

      knownPostIdsRef.current.clear();
      setPosts([]);
    } catch (err) {
      console.error("Error resetting chat:", err);
      setError("The chat could not be reset. Please try again.");
    }
  };

  // ----------------------------
  // Render component
  // ----------------------------
  const orderedPosts = [...posts].sort((firstPost, secondPost) =>
    firstPost.id - secondPost.id,
  );

  return (
    <div className="bulletin-container">
      <div className="glass-form">
        <button
          type="button"
          className="reset-chat-button"
          onClick={handleReset}
          aria-label="Reset chat for everyone"
          title="Reset chat for everyone"
        >
          ↺
        </button>

        <div className="board-topbar">
          <span className="current-user">
            <strong style={{ color: getNameColor(displayName) }}>
              {displayName || "..."}
            </strong>
          </span>
          <button
            type="button"
            className="change-name-button"
            onClick={openNameEditor}
          >
            Change name
          </button>
        </div>

        <h2>Bulletin Board</h2>

        <div className="posts" ref={postsRef} aria-live="polite">
          {orderedPosts.length === 0 ? (
            <p className="no-posts">No posts yet.</p>
          ) : (
            orderedPosts.map((post) => (
              <div className="post" key={post.id}>
                <div className="post-header">
                  <strong style={{ color: getNameColor(post.name) }}>
                    {post.name}
                  </strong>
                  <span>{post.creationTime || ""}</span>
                </div>
                <p>{post.message || post.name}</p>
              </div>
            ))
          )}
        </div>

        <form onSubmit={handleSubmit} className="bulletin-form">
          <div className="form-row">
            <div className="form-group">
              <input
                id="message"
                type="text"
                maxLength={500}
                required
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                placeholder="Write your message here"
              />
            </div>

            <button type="submit" className="send-button">
              Send
            </button>
          </div>
          {error && <p role="alert">{error}</p>}
        </form>
      </div>

      {isNameDialogOpen && (
        <div className="name-dialog-backdrop">
          <div
            className="name-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="name-dialog-title"
          >
            <h3 id="name-dialog-title">
              {displayName ? "Change your name" : "Choose your name"}
            </h3>
            <p>
              Your name is saved in this browser and used for your future
              posts.
            </p>

            <form onSubmit={handleNameSubmit}>
              <label htmlFor="display-name">Name</label>
              <input
                id="display-name"
                type="text"
                maxLength={80}
                value={nameDraft}
                onChange={(e) => {
                  setNameDraft(e.target.value);
                  setNameError("");
                }}
                placeholder="Your name"
                autoFocus
                required
              />
              {nameError && <p role="alert">{nameError}</p>}
              <div className="name-dialog-actions">
                <button type="submit">
                  {displayName ? "Save name" : "Continue"}
                </button>
                {displayName && (
                  <button
                    type="button"
                    className="secondary-button"
                    onClick={() => setIsNameDialogOpen(false)}
                  >
                    Cancel
                  </button>
                )}
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
