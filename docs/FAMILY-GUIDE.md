# ARK Family Guide

A non-technical guide for families who want to run their own AI server at home. No cloud subscriptions, no data leaving your house, always available.

---

## Why Run Your Own AI Server?

### Privacy

Every question you ask ChatGPT, Google Gemini, or Copilot is stored on their servers. They use your conversations to train future models. Your kids' homework questions, your medical questions, your legal questions, your creative writing -- all of it becomes their training data.

With Ark, your conversations never leave your house. The AI runs on hardware you own, in your closet or office. There is no account with OpenAI. There is no data collection. There is no "we updated our privacy policy" email.

### No Tracking

Commercial AI services build profiles on your family. They know what your kids are studying, what you are worried about, what projects you are working on. Ark has zero telemetry. It does not phone home. It does not even need an internet connection to work.

### No Subscriptions

ChatGPT Plus costs $20/month per user. A family of four is $80/month, or $960/year. And if OpenAI raises prices or changes terms, you have no choice but to pay or lose access.

Ark costs nothing after the hardware. Your only ongoing cost is electricity.

### Always Available

Cloud AI services go down. They have rate limits. They get slow during peak hours. Your Ark server is on your network, always ready, with no queue and no rate limits.

---

## Hardware Recommendations

You need one computer with a powerful graphics card (GPU). The GPU is what actually runs the AI models.

### Budget: ~$500

- Used desktop with an NVIDIA RTX 3090 (24 GB VRAM)
- Source: eBay, Facebook Marketplace, r/hardwareswap
- Runs: Most 7B-13B models comfortably, some 30B+ models slowly
- Good for: Homework help, writing assistance, basic image generation

### Mid-Range: ~$1,500

- Desktop with an NVIDIA RTX 4090 (24 GB VRAM)
- Runs: 35B parameter models at good speed, image generation
- Good for: Everything the budget tier does, plus faster responses and better code generation

### Premium: ~$2,500+

- Desktop with an NVIDIA RTX 5090 (32 GB VRAM)
- Runs: The largest consumer-accessible models with room to spare
- Good for: The best local AI experience available, rivaling cloud services

### Other Requirements

- 32 GB RAM minimum (64-96 GB recommended)
- 1 TB NVMe SSD (AI models are large -- 20-50 GB each)
- Any modern CPU (AMD Ryzen 7/9 or Intel i7/i9)
- Ubuntu 24.04 (free Linux operating system)

---

## What Your Family Gets

### Private ChatGPT Equivalent

Open WebUI gives every family member their own login with a familiar chat interface. It looks and works like ChatGPT: type a question, get an answer. Conversations are saved per-user and stay on your server.

Access it from any device on your home network at: **http://ark-server:3000**

### Homework Help

Ask the AI to explain concepts, check math, practice vocabulary, write essay outlines, quiz you on material, or walk through problems step by step. Unlike ChatGPT, there is no monthly limit on usage.

### Creative Writing

Story ideas, character development, poetry, song lyrics, scripts. The AI can brainstorm, draft, and revise with you. Some models are specifically tuned for creative work.

### Image Generation

ComfyUI lets you generate images from text descriptions. Describe what you want ("a watercolor painting of a cat reading a book in a library") and the AI creates it. Great for school projects, gifts, or fun.

### Offline Knowledge (via Kiwix)

Optionally install Kiwix to serve offline copies of Wikipedia, Khan Academy, Stack Exchange, and other educational resources. No internet required.

---

## Setting Up Kid Accounts

### Create separate logins

1. Log into Open WebUI as the admin (the first account created during setup)
2. Go to **Admin Panel** (gear icon) > **Users**
3. Click **Add User**
4. Enter a name, email (can be fake, e.g., `kid1@ark.local`), and password
5. Set role to **User** (not Admin)

### Restrict available models

Not all models are appropriate for kids. Some "uncensored" models will answer anything without safety filters.

1. Go to **Admin Panel > Settings > Models**
2. For each model, set visibility: **Public** (everyone sees it) or **Admin Only**
3. Keep safe, general-purpose models public: `qwen3.5:35b`, `llama3.1:8b`
4. Mark uncensored or experimental models as Admin Only

### What kids can do

- Chat with available models
- Upload documents for the AI to read and answer questions about
- Search their conversation history
- Use different models for different tasks

### What kids cannot do (as User role)

- See or use admin-only models
- Access admin settings
- Create or delete other accounts
- Change system prompts or model configurations

---

## Keeping Uncensored Models Separate

Some models (like Dolphin variants) are intentionally uncensored -- they will discuss any topic without refusal. These are useful for adults (creative writing, research, understanding sensitive topics) but not appropriate for kids.

**How to keep them separate:**

1. Pull the uncensored model: `ollama pull dolphin-mistral`
2. In Open WebUI admin settings, set the model visibility to **Admin Only**
3. Only admin accounts can see and use it
4. Kid accounts will never see it in their model list

---

## Monthly Cost

After buying the hardware, the only ongoing cost is electricity.

| Usage Level | Monthly Power Cost |
|-------------|-------------------|
| Light (few hours/day) | $10-15 |
| Moderate (8+ hours/day) | $20-30 |
| Heavy (always on, frequent generation) | $30-40 |

These estimates assume US electricity rates (~$0.12/kWh) and an RTX 4090/5090 system.

The server can be turned off when not in use to save power, but most people leave it running for convenience.

---

## Comparison: Ark vs. ChatGPT Plus

| | ChatGPT Plus | Ark |
|--|-------------|-----|
| Monthly cost | $20/user ($80 for family of 4) | $0 (electricity only: ~$20-40) |
| Annual cost | $960+ | $240-480 (electricity) |
| Privacy | OpenAI stores all conversations | Everything stays in your house |
| Internet required | Yes, always | No (works offline) |
| Rate limits | Yes (40 messages/3 hours on GPT-4) | No limits |
| Model choice | Whatever OpenAI offers | You choose from hundreds of models |
| Image generation | DALL-E (limited) | Flux, Stable Diffusion (unlimited) |
| Custom models | No | Yes, run any open-weight model |
| Data ownership | OpenAI owns it | You own it |
| Uptime | Depends on OpenAI | Depends on your power |
| Setup difficulty | Sign up, pay | Needs technical setup (one-time) |
| Hardware cost | $0 | $500-2500 (one-time) |

**Break-even for a family of four:** ~6-12 months depending on hardware choice.

---

## Getting Started

If this sounds right for your family, here is the path:

1. **Get the hardware.** A used RTX 3090 desktop is the most affordable entry point.
2. **Find your tech person.** Someone needs to install Ubuntu and run the Ark installer. It takes about an hour. See `DEPLOYMENT.md`.
3. **Create accounts.** Each family member gets their own login.
4. **Bookmark the URL.** `http://ark-server:3000` on every device.
5. **Start using it.** It works just like ChatGPT. Type and go.

If you do not have a tech person in the family, look for a local Linux user group, or a tech-savvy friend. The install is a one-time event. After that, it just runs.

---

## Frequently Asked Questions

**Is it as good as ChatGPT?**
For most tasks, yes. The latest open-weight models (Qwen, Llama, DeepSeek) are competitive with GPT-4 for general conversation, homework, and writing. They are slightly weaker at very complex reasoning tasks, but this gap closes every few months.

**Can I use it from my phone?**
Yes. Open WebUI works in any mobile browser. Just navigate to your server's address on your home WiFi. For access away from home, set up WireGuard VPN (see `VPN.md`).

**What if the AI says something wrong?**
Same rules as ChatGPT: AI can be wrong. Teach your kids to verify important information from other sources. The AI is a tool, not an authority.

**Can my kids bypass the model restrictions?**
Not through Open WebUI. The model visibility is controlled server-side. They would need the admin password to change it.

**What if the hardware breaks?**
Chat histories are stored on the SSD. If the GPU dies, replace it and everything else is preserved. Regular backups of `/opt/ark/data/` to an external drive are recommended.

**Can I add more GPUs later?**
Technically yes, but it requires more advanced configuration. Most families will do fine with a single GPU.
