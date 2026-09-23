//! pacgate-memory — OpenViking long-term memory bridge for pacgate-ai.
//!
//! Provides a thin, typed client over OpenViking's REST API so pacgate-ai
//! workflows and metadata can persist and recall long-term memory (semantic
//! vector memory) instead of only the per-matter `memory.json` file.
//!
//! ## Endpoints used
//! - `POST /api/v1/search/find`  — semantic recall across memory/resources/skills
//! - `POST /api/v1/content/write` — persist text to a `viking://` memory URI
//!
//! ## Auth
//! OpenViking's ROOT API key cannot access tenant-scoped data APIs. A user or
//! admin API key is required (minted via `POST /api/v1/admin/accounts/{id}/users`).
//! The key is read from `OPENVIKING_API_KEY` (or `OPENVIKING_USER_API_KEY`).

use serde::{Deserialize, Serialize};

/// A single recalled memory item from OpenViking semantic search.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryHit {
    pub context_type: String,
    pub uri: String,
    #[serde(default)]
    pub level: i64,
    #[serde(default)]
    pub score: f64,
    #[serde(default)]
    pub r#abstract: String,
    #[serde(default)]
    pub tags: Vec<String>,
}

/// The `find` response body (memories + resources + skills).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FindResult {
    #[serde(default)]
    pub memories: Vec<MemoryHit>,
    #[serde(default)]
    pub resources: Vec<MemoryHit>,
    #[serde(default)]
    pub skills: Vec<MemoryHit>,
}

impl FindResult {
    /// Flatten all hits into a single list, ordered by score descending.
    pub fn all_hits(&self) -> Vec<&MemoryHit> {
        let mut hits: Vec<&MemoryHit> = self
            .memories
            .iter()
            .chain(self.resources.iter())
            .chain(self.skills.iter())
            .collect();
        hits.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
        hits
    }
}

/// OpenViking REST client.
#[derive(Clone)]
pub struct OpenVikingClient {
    base_url: String,
    api_key: String,
    http: reqwest::Client,
}

#[derive(Debug, thiserror::Error)]
pub enum MemoryError {
    #[error("openviking request failed: {0}")]
    Request(#[from] reqwest::Error),
    #[error("openviking returned error status {status}: {body}")]
    Api { status: u16, body: String },
    #[error("openviking response missing expected field: {0}")]
    MissingField(String),
}

impl OpenVikingClient {
    /// Build a client from environment variables.
    ///
    /// - `OPENVIKING_BASE_URL` (default `http://openviking:1933`)
    /// - `OPENVIKING_USER_API_KEY` (user/admin key; preferred) or
    ///   `OPENVIKING_API_KEY` (fallback). The ROOT key is rejected for data APIs.
    pub fn from_env() -> Result<Self, MemoryError> {
        let base_url = std::env::var("OPENVIKING_BASE_URL")
            .unwrap_or_else(|_| "http://openviking:1933".to_string());
        let api_key = std::env::var("OPENVIKING_USER_API_KEY")
            .or_else(|_| std::env::var("OPENVIKING_API_KEY"))
            .map_err(|_| MemoryError::MissingField("OPENVIKING_USER_API_KEY".to_string()))?;
        Ok(Self::new(base_url, api_key))
    }

    pub fn new(base_url: impl Into<String>, api_key: impl Into<String>) -> Self {
        Self {
            base_url: base_url.into().trim_end_matches('/').to_string(),
            api_key: api_key.into(),
            http: reqwest::Client::new(),
        }
    }

    /// Semantic recall across long-term memory.
    pub async fn find(&self, query: &str, limit: usize) -> Result<FindResult, MemoryError> {
        let body = serde_json::json!({
            "query": query,
            "limit": limit,
        });
        let resp = self
            .http
            .post(format!("{}/api/v1/search/find", self.base_url))
            .header("X-API-Key", &self.api_key)
            .json(&body)
            .send()
            .await?;

        let status = resp.status();
        let text = resp.text().await?;
        if !status.is_success() {
            return Err(MemoryError::Api {
                status: status.as_u16(),
                body: text,
            });
        }

        let value: serde_json::Value = serde_json::from_str(&text)
            .map_err(|e| MemoryError::MissingField(format!("invalid JSON: {e}")))?;
        let result = value
            .get("result")
            .cloned()
            .ok_or_else(|| MemoryError::MissingField("result".to_string()))?;
        serde_json::from_value(result)
            .map_err(|e| MemoryError::MissingField(format!("result shape: {e}")))
    }

    /// Persist text content to a `viking://` memory URI.
    ///
    /// `mode` is one of `create`, `replace`, `append`.
    pub async fn write(
        &self,
        uri: &str,
        content: &str,
        mode: &str,
    ) -> Result<(), MemoryError> {
        let body = serde_json::json!({
            "uri": uri,
            "content": content,
            "mode": mode,
        });
        let resp = self
            .http
            .post(format!("{}/api/v1/content/write", self.base_url))
            .header("X-API-Key", &self.api_key)
            .json(&body)
            .send()
            .await?;

        let status = resp.status();
        let text = resp.text().await?;
        if !status.is_success() {
            return Err(MemoryError::Api {
                status: status.as_u16(),
                body: text,
            });
        }
        Ok(())
    }
}
