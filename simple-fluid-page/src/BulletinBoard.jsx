import React, { useState, useEffect } from "react";
import "./BulletinBoard.css";

export default function BulletinBoard() {
  const [name, setName] = useState("");
  const [message, setMessage] = useState("");
  const [posts, setPosts] = useState([]);

  // Hämta poster (posts) från backend vid start
  useEffect(() => {
    fetch("http://localhost:8080/api/posts")
      .then((res) => res.json())
      .then(setPosts)
      .catch(console.error);
  }, []);

  // Hantera inlämning av ny post
  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!message.trim()) return;

    const newPost = {
      id: Date.now(),
      name: name || "Anonymous",
      message,
      isComplete: false,
    };

    await fetch("http://localhost:8080/api/posts", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(newPost),
    });

    setName("");
    setMessage("");

    const updated = await fetch("http://localhost:8080/api/posts").then((res) =>
      res.json()
    );
    setPosts(updated);
  };

  return (
    <div className="bulletin-container">
      <div className="glass-form">
        <h2>Bulletin Board</h2>

        <form onSubmit={handleSubmit} className="bulletin-form">
          <div className="form-row">
            <div className="form-group">
              <label htmlFor="name">Name</label>
              <input
                id="name"
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Your name"
              />
            </div>

            <div className="form-group">
              <label htmlFor="message">Message</label>
              <input
                id="message"
                type="text"
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                placeholder="Write your message here"
              />
            </div>
          </div>

          <button type="submit">Post</button>
        </form>
      </div>

      <div className="posts">
        {posts.length === 0 ? (
          <p className="no-posts">No posts yet.</p>
        ) : (
          posts.map((post) => (
            <div className="post" key={post.id}>
              <div className="post-header">
                <strong>{post.name}</strong>
                <span>{post.creationTime || ""}</span>
              </div>
              <p>{post.message || post.name}</p>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
