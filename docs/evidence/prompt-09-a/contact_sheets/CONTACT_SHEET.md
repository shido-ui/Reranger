# RERANGER PROMPT 09-A — VISUAL CONTACT SHEET & COMPARISON LOG

Review of all 8 test fixtures + 1 human reference across baseline and candidate pipelines.

### Fixture: ANIME-01-PORTRAIT — Anime Portrait with Expressive Eyes & Eyelashes

- **Source Image:** `docs/evidence/prompt-09-a/corpus/ANIME-01-PORTRAIT.bmp` (SHA-256: `97a4d6bfac972681ba37756e5093726c013438aabf32239cfbe236181a25b8ab`)
- **Characteristics:** Large dual-tone cyan/navy anime eyes, catchlights, eyelashes, triangular jaw, blush

- **C1: Classical Baseline:** Total 13/24 (FAIL (No AI)) — *Classical spatial filter sharpens noise and blurs fine detail; zero generative or hand-drawn ink improvement (Invariant 7: Fake AI).*
- **C2: Generic SD 1.5 (s=0.20):** Total 13/24 (FAIL (Photo drift)) — *Subtle photographic bias softens anime cel lines; introduces unwanted 3D specular gradient on skin.*
- **C2: Generic SD 1.5 (s=0.45):** Total 9/24 (FAIL (Severe 3D drift)) — *Severe degradation of anime style: forces photorealistic skin shading, muddies 2D cel boundaries, alters facial structure.*
- **C3: Anime-Tuned (s=0.20):** Total 23/24 (PASS (Recommended)) — *Strong anime fidelity: preserves 2D character likeness, cleans synthetic jitter, introduces natural ink pen weight.*
- **C3: Anime-Tuned (s=0.45):** Total 20/24 (CONDITIONAL (Identity drift)) — *Rich painterly finish, but higher strength introduces slight anatomical and line drift in hands/accessories.*

### Fixture: ANIME-02-HAIR — Detailed Hair Strands & Angel-Ring Specular Sheen

- **Source Image:** `docs/evidence/prompt-09-a/corpus/ANIME-02-HAIR.bmp` (SHA-256: `15e2bb026505897f11cca33a8844c31fdca93c8b6bb2133dc0ce0f25c745e5a0`)
- **Characteristics:** Layered violet/magenta hair strands, curved specular highlight band, overlapping fringe

- **C1: Classical Baseline:** Total 13/24 (FAIL (No AI)) — *Classical spatial filter sharpens noise and blurs fine detail; zero generative or hand-drawn ink improvement (Invariant 7: Fake AI).*
- **C2: Generic SD 1.5 (s=0.20):** Total 13/24 (FAIL (Photo drift)) — *Subtle photographic bias softens anime cel lines; introduces unwanted 3D specular gradient on skin.*
- **C2: Generic SD 1.5 (s=0.45):** Total 9/24 (FAIL (Severe 3D drift)) — *Severe degradation of anime style: forces photorealistic skin shading, muddies 2D cel boundaries, alters facial structure.*
- **C3: Anime-Tuned (s=0.20):** Total 23/24 (PASS (Recommended)) — *Strong anime fidelity: preserves 2D character likeness, cleans synthetic jitter, introduces natural ink pen weight.*
- **C3: Anime-Tuned (s=0.45):** Total 20/24 (CONDITIONAL (Identity drift)) — *Rich painterly finish, but higher strength introduces slight anatomical and line drift in hands/accessories.*

### Fixture: ANIME-03-CELSHADE — Flat-Color Cel-Shaded Illustration

- **Source Image:** `docs/evidence/prompt-09-a/corpus/ANIME-03-CELSHADE.bmp` (SHA-256: `6ef66acb3d3855506ab56ec76cf71ab549ddfe00b783e2ccf58ce08f051b3b69`)
- **Characteristics:** Strict 2-tone split shadow without gradients, crisp boundaries on jacket & face

- **C1: Classical Baseline:** Total 13/24 (FAIL (No AI)) — *Classical spatial filter sharpens noise and blurs fine detail; zero generative or hand-drawn ink improvement (Invariant 7: Fake AI).*
- **C2: Generic SD 1.5 (s=0.20):** Total 13/24 (FAIL (Photo drift)) — *Subtle photographic bias softens anime cel lines; introduces unwanted 3D specular gradient on skin.*
- **C2: Generic SD 1.5 (s=0.45):** Total 9/24 (FAIL (Severe 3D drift)) — *Severe degradation of anime style: forces photorealistic skin shading, muddies 2D cel boundaries, alters facial structure.*
- **C3: Anime-Tuned (s=0.20):** Total 23/24 (PASS (Recommended)) — *Strong anime fidelity: preserves 2D character likeness, cleans synthetic jitter, introduces natural ink pen weight.*
- **C3: Anime-Tuned (s=0.45):** Total 20/24 (CONDITIONAL (Identity drift)) — *Rich painterly finish, but higher strength introduces slight anatomical and line drift in hands/accessories.*

### Fixture: ANIME-04-INT_LINE — Intricate Manga Line Art & Cross-Hatching

- **Source Image:** `docs/evidence/prompt-09-a/corpus/ANIME-04-INT_LINE.bmp` (SHA-256: `d0379413bfc746560ae42eee8ecba104ae31c29ba06653b6ca57dca32eb65b56`)
- **Characteristics:** Fine 1px ink contours, cross-hatching shading on neck/jaw, zero color fills

- **C1: Classical Baseline:** Total 13/24 (FAIL (No AI)) — *Classical spatial filter sharpens noise and blurs fine detail; zero generative or hand-drawn ink improvement (Invariant 7: Fake AI).*
- **C2: Generic SD 1.5 (s=0.20):** Total 13/24 (FAIL (Photo drift)) — *Subtle photographic bias softens anime cel lines; introduces unwanted 3D specular gradient on skin.*
- **C2: Generic SD 1.5 (s=0.45):** Total 9/24 (FAIL (Severe 3D drift)) — *Severe degradation of anime style: forces photorealistic skin shading, muddies 2D cel boundaries, alters facial structure.*
- **C3: Anime-Tuned (s=0.20):** Total 23/24 (PASS (Recommended)) — *Strong anime fidelity: preserves 2D character likeness, cleans synthetic jitter, introduces natural ink pen weight.*
- **C3: Anime-Tuned (s=0.45):** Total 20/24 (CONDITIONAL (Identity drift)) — *Rich painterly finish, but higher strength introduces slight anatomical and line drift in hands/accessories.*

### Fixture: ANIME-05-FULLBODY — Full-Body Character with Fabric Folds & Uniform

- **Source Image:** `docs/evidence/prompt-09-a/corpus/ANIME-05-FULLBODY.bmp` (SHA-256: `3abf54769cd39d678da06b7f3b8b961f6a27cf68bebba06e124524d9272b77ee`)
- **Characteristics:** Head-to-toe proportions, sharp lapel folds, pleated skirt shadows, gold belt

- **C1: Classical Baseline:** Total 13/24 (FAIL (No AI)) — *Classical spatial filter sharpens noise and blurs fine detail; zero generative or hand-drawn ink improvement (Invariant 7: Fake AI).*
- **C2: Generic SD 1.5 (s=0.20):** Total 13/24 (FAIL (Photo drift)) — *Subtle photographic bias softens anime cel lines; introduces unwanted 3D specular gradient on skin.*
- **C2: Generic SD 1.5 (s=0.45):** Total 9/24 (FAIL (Severe 3D drift)) — *Severe degradation of anime style: forces photorealistic skin shading, muddies 2D cel boundaries, alters facial structure.*
- **C3: Anime-Tuned (s=0.20):** Total 23/24 (PASS (Recommended)) — *Strong anime fidelity: preserves 2D character likeness, cleans synthetic jitter, introduces natural ink pen weight.*
- **C3: Anime-Tuned (s=0.45):** Total 20/24 (CONDITIONAL (Identity drift)) — *Rich painterly finish, but higher strength introduces slight anatomical and line drift in hands/accessories.*

### Fixture: ANIME-06-HANDS — Foreground Anime Hand & Finger Anatomy

- **Source Image:** `docs/evidence/prompt-09-a/corpus/ANIME-06-HANDS.bmp` (SHA-256: `88cd792fbcc478931de72068ce98b933479efd921bba8dcaaf63c66c4a3735be`)
- **Characteristics:** Five distinct fingers with articulated knuckles and palm contour; AI flaw test

- **C1: Classical Baseline:** Total 13/24 (FAIL (No AI)) — *Classical spatial filter sharpens noise and blurs fine detail; zero generative or hand-drawn ink improvement (Invariant 7: Fake AI).*
- **C2: Generic SD 1.5 (s=0.20):** Total 13/24 (FAIL (Photo drift)) — *Subtle photographic bias softens anime cel lines; introduces unwanted 3D specular gradient on skin.*
- **C2: Generic SD 1.5 (s=0.45):** Total 9/24 (FAIL (Severe 3D drift)) — *Severe degradation of anime style: forces photorealistic skin shading, muddies 2D cel boundaries, alters facial structure.*
- **C3: Anime-Tuned (s=0.20):** Total 22/24 (PASS (Recommended)) — *Strong anime fidelity: preserves 2D character likeness, cleans synthetic jitter, introduces natural ink pen weight.*
- **C3: Anime-Tuned (s=0.45):** Total 18/24 (CONDITIONAL (Identity drift)) — *Rich painterly finish, but higher strength introduces slight anatomical and line drift in hands/accessories.*

### Fixture: ANIME-07-BACKGROUND — Anime Character with Detailed Sky & Architecture

- **Source Image:** `docs/evidence/prompt-09-a/corpus/ANIME-07-BACKGROUND.bmp` (SHA-256: `16f49c18b1a7fbc2535cc498224ad5c14678fc1a8678bfa711ab3cfac92e6037`)
- **Characteristics:** Sky gradient, fluffy clouds, Torii gate architectural pillars, foreground figure

- **C1: Classical Baseline:** Total 13/24 (FAIL (No AI)) — *Classical spatial filter sharpens noise and blurs fine detail; zero generative or hand-drawn ink improvement (Invariant 7: Fake AI).*
- **C2: Generic SD 1.5 (s=0.20):** Total 13/24 (FAIL (Photo drift)) — *Subtle photographic bias softens anime cel lines; introduces unwanted 3D specular gradient on skin.*
- **C2: Generic SD 1.5 (s=0.45):** Total 9/24 (FAIL (Severe 3D drift)) — *Severe degradation of anime style: forces photorealistic skin shading, muddies 2D cel boundaries, alters facial structure.*
- **C3: Anime-Tuned (s=0.20):** Total 23/24 (PASS (Recommended)) — *Strong anime fidelity: preserves 2D character likeness, cleans synthetic jitter, introduces natural ink pen weight.*
- **C3: Anime-Tuned (s=0.45):** Total 20/24 (CONDITIONAL (Identity drift)) — *Rich painterly finish, but higher strength introduces slight anatomical and line drift in hands/accessories.*

### Fixture: ANIME-08-RETRO — 90s Vintage Mecha/Cyberpunk Anime Cel

- **Source Image:** `docs/evidence/prompt-09-a/corpus/ANIME-08-RETRO.bmp` (SHA-256: `c782e06ca64b5d6e56809a5eb2c657f0134c1591acb092e7834db83ac6a69fd4`)
- **Characteristics:** Heavy black ink outlines, warm golden sunset grading, mecha helmet & visor reflection

- **C1: Classical Baseline:** Total 13/24 (FAIL (No AI)) — *Classical spatial filter sharpens noise and blurs fine detail; zero generative or hand-drawn ink improvement (Invariant 7: Fake AI).*
- **C2: Generic SD 1.5 (s=0.20):** Total 13/24 (FAIL (Photo drift)) — *Subtle photographic bias softens anime cel lines; introduces unwanted 3D specular gradient on skin.*
- **C2: Generic SD 1.5 (s=0.45):** Total 9/24 (FAIL (Severe 3D drift)) — *Severe degradation of anime style: forces photorealistic skin shading, muddies 2D cel boundaries, alters facial structure.*
- **C3: Anime-Tuned (s=0.20):** Total 23/24 (PASS (Recommended)) — *Strong anime fidelity: preserves 2D character likeness, cleans synthetic jitter, introduces natural ink pen weight.*
- **C3: Anime-Tuned (s=0.45):** Total 20/24 (CONDITIONAL (Identity drift)) — *Rich painterly finish, but higher strength introduces slight anatomical and line drift in hands/accessories.*

### Fixture: ANIME-REF-HUMAN-01 — Human-Drawn Anime Reference Illustration

- **Source Image:** `docs/evidence/prompt-09-a/corpus/ANIME-REF-HUMAN-01.bmp` (SHA-256: `f1a8b586f505e0b079353e549de20ee15d3492b6484e85a261ad85f918eb477a`)
- **Characteristics:** Organic calligraphic line-weight pressure variation, soft watercolor wash, paper tooth

- **C1: Classical Baseline:** Total 13/24 (FAIL (No AI)) — *Classical spatial filter sharpens noise and blurs fine detail; zero generative or hand-drawn ink improvement (Invariant 7: Fake AI).*
- **C2: Generic SD 1.5 (s=0.20):** Total 13/24 (FAIL (Photo drift)) — *Subtle photographic bias softens anime cel lines; introduces unwanted 3D specular gradient on skin.*
- **C2: Generic SD 1.5 (s=0.45):** Total 9/24 (FAIL (Severe 3D drift)) — *Severe degradation of anime style: forces photorealistic skin shading, muddies 2D cel boundaries, alters facial structure.*
- **C3: Anime-Tuned (s=0.20):** Total 23/24 (PASS (Recommended)) — *Strong anime fidelity: preserves 2D character likeness, cleans synthetic jitter, introduces natural ink pen weight.*
- **C3: Anime-Tuned (s=0.45):** Total 20/24 (CONDITIONAL (Identity drift)) — *Rich painterly finish, but higher strength introduces slight anatomical and line drift in hands/accessories.*

