---
name: web-development
description: HTML, CSS, JavaScript ve modern web framework'leri (Next.js, Vite, React) ile web sitesi geliştirme kuralları. Modern tasarım, SEO, responsive layout ve performans optimizasyonu.
---

# Web Geliştirme Yeteneği (Skill)

Bu skill, web sitesi ve web uygulaması projelerinde yapay zekanın (benim) profesyonel bir frontend mühendisi gibi davranmamı sağlar.

## Tasarım Prensipleri
- **İlk bakışta etkileyici** bir tasarım yap. Sade ama premium görünüm.
- Generic renkler (düz kırmızı, mavi, yeşil) kullanma. Uyumlu, küratörlüğü yapılmış renk paletleri kullan.
- Modern tipografi kullan (Google Fonts: Inter, Roboto, Outfit vb.)
- Smooth gradientler, glassmorphism efektleri, mikro-animasyonlar ekle.
- Hover efektleri ve interaktif elementler ile canlı bir arayüz oluştur.
- **Placeholder kullanma**, gerçek görsel lazımsa `generate_image` aracını kullan.

## HTML & Semantik
- Semantik HTML5 elementleri kullan: `<header>`, `<main>`, `<section>`, `<article>`, `<nav>`, `<footer>`
- Sayfa başına tek bir `<h1>`, doğru başlık hiyerarşisi (`h1` > `h2` > `h3`).
- Tüm interaktif elementlere benzersiz, açıklayıcı `id` ver.
- Tüm görsellere `alt` text ekle.

## CSS
- Vanilla CSS kullan (Tailwind istenmediği sürece).
- CSS Custom Properties (variables) kullanarak tutarlı bir tasarım sistemi oluştur:
  ```css
  :root {
    --color-primary: #6366f1;
    --color-surface: #0f0f0f;
    --radius-md: 12px;
    --font-sans: 'Inter', sans-serif;
  }
  ```
- Mobile-first responsive tasarım yap.
- Smooth transitions ve animasyonlar ekle (`transition`, `@keyframes`).

## JavaScript
- Modern ES6+ sözdizimi kullan (arrow functions, destructuring, template literals).
- `var` kullanma, `const` ve `let` tercih et.
- Async/await kalıbını kullan (callback hell'den kaçın).

## SEO (Her Sayfada Otomatik)
- Açıklayıcı `<title>` tag'ı ekle.
- `<meta name="description">` ile sayfa açıklaması yaz.
- Open Graph meta tag'ları ekle (`og:title`, `og:description`, `og:image`).
- Hızlı sayfa yükleme süresi sağla.

## Performans
- Görselleri optimize et (WebP formatı, lazy loading).
- CSS ve JS dosyalarını minimize et.
- Critical CSS'i inline yap.
- `defer` ve `async` attribute'larını script'lerde kullan.

## Erişilebilirlik (Accessibility)
- ARIA label'ları kullan.
- Klavye navigasyonunu destekle.
- Yeterli renk kontrastı sağla.
- Focus state'lerini görünür yap.
