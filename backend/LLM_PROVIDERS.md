# LLM Provider Configuration

The app now uses LangChain for LLM interactions, making it easy to switch between different providers.

## Supported Providers

- **Gemini** (Google) - Default
- **Claude** (Anthropic) - Ready to use

## How to Switch Providers

### Using Gemini (Default)

Add to `.env`:
```bash
LLM_PROVIDER=gemini
GEMINI_API_KEY=your_gemini_api_key
```

### Using Claude

Add to `.env`:
```bash
LLM_PROVIDER=claude
ANTHROPIC_API_KEY=your_anthropic_api_key
```

## Files

- `app/services/llm_service.py` - Main service (routes to LangChain)
- `app/services/llm_service_langchain.py` - LangChain implementation
- `app/config.py` - Provider configuration

## Benefits

✅ **Provider-agnostic**: Switch between Gemini, Claude, or add new providers easily
✅ **Tool calling**: Works with all providers that support function calling
✅ **Streaming**: Maintains paragraph and tool call interleaving
✅ **Backward compatible**: Legacy GenAI implementation still available

## Adding a New Provider

1. Install the LangChain integration (e.g., `langchain-openai`)
2. Add to `_get_llm_model()` in `llm_service_langchain.py`:
   ```python
   elif model_type == "openai":
       from langchain_openai import ChatOpenAI
       return ChatOpenAI(
           model="gpt-4",
           openai_api_key=settings.OPENAI_API_KEY,
           temperature=0.7,
       )
   ```
3. Add `OPENAI_API_KEY` to `config.py`
4. Set `LLM_PROVIDER=openai` in `.env`

## Fallback to Legacy

To use the original Google GenAI SDK (without LangChain):

In `llm_service.py`, change:
```python
use_langchain: bool = True  # Default
```
to:
```python
use_langchain: bool = False
```
