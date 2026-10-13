---
name: flutter-best-practices
description: Flutter & Dart geliştirme için en iyi pratikler, widget mimarisi, performans optimizasyonu ve test stratejileri. GitHub'daki en popüler Flutter kurallarından (awesome-cursorrules 40K⭐, VoltAgent 27K⭐) derlenmiştir.
---

# Flutter & Dart Geliştirme Yeteneği (Skill)

Bu skill, Flutter mobil uygulama geliştirme projelerinde yapay zekanın (benim) üst düzey bir Flutter mühendisi gibi davranmamı sağlar.

## Widget Mimarisi

### Widget Oluşturma Kuralları
- Widget'ları **ayrı sınıflar** olarak oluştur, asla helper method ile widget döndürme.
- Her widget tek bir sorumluluk taşısın.
- Mümkün olan her yerde `const` constructor kullan — bu Flutter'ın rebuild mekanizmasını optimize eder.
- Derin iç içe widget ağaçlarından kaçın (max 3-4 seviye), gerekirse küçük widget'lara böl.

### Layout
- `Row` ve `Column` widget'larında `spacing` özelliğini kullan, araya `SizedBox` koyma.
- `Expanded` ve `Flexible` widget'larını doğru kullan.
- `ListView.builder` kullan (büyük listelerde), `ListView` (children:) kullanma.

### Tema ve Renkler
- **Asla hardcoded renk kullanma!** `Colors.white`, `Colors.black` yerine:
  ```dart
  Theme.of(context).colorScheme.surface
  Theme.of(context).colorScheme.onSurface
  Theme.of(context).colorScheme.primary
  ```
- `TextStyle` objesi manuel oluşturma, tema text style'larını kullan:
  ```dart
  Theme.of(context).textTheme.titleLarge
  Theme.of(context).textTheme.bodyMedium
  ```
- `.withValues(alpha: 0.5)` kullan, `.withOpacity()` deprecated.

## State Management
- Gereksiz `StatefulWidget` kullanma, mümkünse `StatelessWidget` tercih et.
- State yönetimi için projenin mevcut yapısına uy (Riverpod, Bloc, Provider vb.)
- `setState()` çağrılarını minimize et, sadece gerçekten değişen state'i güncelle.

## Performans
- `const` widget'ları agresif kullan.
- `RepaintBoundary` kullanarak gereksiz repaint'leri engelle.
- Animasyonlarda `AnimatedBuilder` veya `TweenAnimationBuilder` tercih et.
- Resimler için `Image.asset` yerine `CachedNetworkImage` (network resimleri için) kullan.
- `ListView.builder` ve `GridView.builder` ile lazy loading uygula.

## Platform Kanalları (Platform Channels)
- Native kodla iletişimde `MethodChannel` kullan.
- Hata yönetimini düzgün yap (`PlatformException` yakala).

## Dosya Yapısı (Önerilen)
```
lib/
├── main.dart
├── app.dart
├── models/          # Veri modelleri
├── services/        # İş mantığı ve API çağrıları
├── screens/         # Tam sayfa ekranlar
├── widgets/         # Tekrar kullanılabilir küçük widget'lar
├── utils/           # Yardımcı fonksiyonlar
├── constants/       # Sabit değerler, renkler, stringler
└── providers/       # State management (Riverpod/Provider/Bloc)
```

## Paket Yönetimi
- `pubspec.yaml`'a paket eklerken versiyon sabitle (^x.x.x).
- Kullanılmayan paketleri kaldır.
- `flutter pub outdated` ile güncellemeleri takip et.
