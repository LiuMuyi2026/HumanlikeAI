"""News search service using Google Custom Search API or web scraping fallback."""

import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional

import httpx
from google import genai

logger = logging.getLogger(__name__)


class NewsSearchService:
    """Search for news using Gemini's grounding with Google Search."""

    def __init__(self, gemini_api_key: str):
        self._client = genai.Client(api_key=gemini_api_key)

    async def search_news(
        self,
        query: str,
        location: Optional[str] = None,
        max_results: int = 5,
    ) -> list[dict]:
        """
        Search for recent news using Gemini with Google Search grounding.

        Returns list of dicts with: title, summary, source, url, timestamp
        """
        search_query = query
        if location:
            search_query = f"{location} {query}"

        prompt = f"""Search for the latest news about: {search_query}

Return the top {max_results} most relevant recent news items.
For each item, provide:
- title: The headline
- summary: 2-3 sentence summary
- source: The news source name
- url: The article URL if available
- date: The publication date if available

Format as a JSON array. Only return the JSON, no other text.
Example: [{{"title": "...", "summary": "...", "source": "...", "url": "...", "date": "..."}}]
"""

        try:
            # Use Gemini with Google Search grounding
            response = await asyncio.to_thread(
                self._client.models.generate_content,
                model="models/gemini-2.0-flash",
                contents=prompt,
                config={
                    "tools": [{"google_search": {}}],
                },
            )

            # Parse the response
            text = response.text.strip()

            # Strip markdown code blocks if present
            if text.startswith("```"):
                lines = text.split("\n")
                lines = lines[1:]
                if lines and lines[-1].strip() == "```":
                    lines = lines[:-1]
                text = "\n".join(lines)

            import json
            news_items = json.loads(text)

            # Add timestamp
            for item in news_items:
                item["fetched_at"] = datetime.now(timezone.utc).isoformat()

            logger.info("Found %d news items for query: %s", len(news_items), search_query)
            return news_items

        except Exception as e:
            logger.warning("News search failed: %s", e)
            return []

    async def search_local_news(
        self,
        user_location: Optional[str] = None,
        ai_location: str = "Tokyo, Japan",  # AI's virtual location
    ) -> list[dict]:
        """Search news for both user's location and AI's virtual location."""
        all_news = []

        # Search user's location news
        if user_location:
            user_news = await self.search_news(
                "latest news today",
                location=user_location,
                max_results=3,
            )
            for item in user_news:
                item["location_type"] = "user"
                item["location"] = user_location
            all_news.extend(user_news)

        # Search AI's location news
        ai_news = await self.search_news(
            "latest news today",
            location=ai_location,
            max_results=3,
        )
        for item in ai_news:
            item["location_type"] = "ai"
            item["location"] = ai_location
        all_news.extend(ai_news)

        return all_news

    async def get_conversation_topics(
        self,
        user_facts: dict,
        user_location: Optional[str] = None,
    ) -> list[str]:
        """Generate conversation topics based on user interests and current news."""

        # Build context from user facts
        interests = []
        if user_facts:
            interests = [
                v for k, v in user_facts.items()
                if k in ("interests", "hobbies", "job", "favorite_topics")
            ]

        prompt = f"""Based on the user's interests and current events, suggest 3 conversation topics.

User interests: {interests if interests else "general topics"}
User location: {user_location or "unknown"}

Search for current news and trending topics, then suggest conversation starters that would be:
1. Relevant to the user's interests
2. Based on recent news or events
3. Engaging and open-ended

Return as a JSON array of strings. Only the JSON, no other text.
Example: ["Have you heard about...", "I was reading that...", "What do you think about..."]
"""

        try:
            response = await asyncio.to_thread(
                self._client.models.generate_content,
                model="models/gemini-2.0-flash",
                contents=prompt,
                config={
                    "tools": [{"google_search": {}}],
                },
            )

            text = response.text.strip()
            if text.startswith("```"):
                lines = text.split("\n")
                lines = lines[1:]
                if lines and lines[-1].strip() == "```":
                    lines = lines[:-1]
                text = "\n".join(lines)

            import json
            topics = json.loads(text)
            return topics

        except Exception as e:
            logger.warning("Failed to generate topics: %s", e)
            return [
                "How has your day been so far?",
                "Is there anything on your mind you'd like to talk about?",
                "What are you looking forward to this week?",
            ]
