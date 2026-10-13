# Flutter Projesi Kuralları (AGENTS.md)
# Kaynak: awesome-cursorrules (40K⭐) + VoltAgent/awesome-agent-skills (27K⭐)

## 🧠 Token Tasarrufu ve İletişim Kuralları
- Kısa ve net cevaplar ver, gereksiz açıklama yapma.
- Dosyanın tamamını baştan yazdırma, sadece değişen bloğu göster/değiştir.
- Kodun ne yaptığını anlatan aşırı yorum satırları ekleme, clean code kendi kendini açıklamalı.
- Kullanıcıya Türkçe cevap ver.

## 🏗️ Mimari ve Temel Prensipler
- Her zaman değişken ve fonksiyonların tiplerini açıkça belirt, `dynamic` kullanma.
- Repository pattern kullan (veri katmanı için).
- Tekrar kullanılabilir kodlar için extension'lar kullan.
- Sabit değerler için constants dosyası kullan, magic number kullanma.
- SOLID prensiplerine uy.
- Composition > Inheritance (kalıtım yerine bileşim tercih et).
- Immutability tercih et, verilerin değişmezliğini koru.

## 📛 İsimlendirme
- PascalCase → Sınıflar (class)
- camelCase → Değişkenler, fonksiyonlar, metodlar
- snake_case → Dosya ve klasör isimleri
- UPPERCASE → Ortam değişkenleri (environment variables)
- Boolean değişkenler: `isLoading`, `hasError`, `canDelete` gibi fiille başlasın.
- Fonksiyon isimleri fiille başlasın: `fetchUser()`, `saveData()`, `executePayment()`
- Kısaltma kullanma (API, URL gibi standart olanlar hariç).

## 🎨 Widget ve UI Kuralları
- Widget'ları küçük, odaklı parçalara böl. Derin iç içe widget kullanma.
- **Ayrı widget sınıfları oluştur**, helper method ile widget döndürme.
- Mümkün olan her yerde `const` constructor kullan.
- Row/Column'da `spacing` özelliğini kullan, araya SizedBox koyma.
- **Hardcoded renk kullanma** (Colors.white, Colors.black vb.), her zaman `Theme.of(context).colorScheme` kullan.
- `TextStyle` objeleri manuel oluşturma, tema text style'larını kullan.
- `.withValues(alpha: value)` kullan, `.withOpacity()` deprecated.

## ⚡ Fonksiyonlar
- Kısa fonksiyonlar yaz (max ~20 satır), tek bir amaç.
- Nesting'i azalt: erken return ve utility fonksiyonları çıkar.
- Basit fonksiyonlar (3 satırdan az) için arrow function kullan.
- Default parametre değerleri kullan, null kontrolü yerine.

## 🧪 Test Kuralları
- Arrange-Act-Assert konvansiyonunu takip et.
- `testWidgets()` ve `WidgetTester` kullan.
- `find.byType()`, `find.text()`, `find.byKey()` ile widget bul.
- `pumpWidget()` ile render, `pump()` ile rebuild tetikle.
- `pumpAndSettle()` animasyonlu/async işlemler için kullan.
- Mock bağımlılıkları `mockito` veya manuel mock ile oluştur.

## 🔒 Hata Yönetimi
- Beklenmeyen hatalar için exception kullan.
- Yakaladığın exception'ı ya düzelt ya da context ekle, yoksa global handler'a bırak.

## 📝 Git Commit Kuralları
- Conventional commit formatı: `<type>[scope]: <description>`
- Tipler: feat, fix, docs, style, refactor, test, chore
- Örnek: `git commit -m "feat: add camera resolution selector"`

## ⚠️ Komut Çalıştırma
- Flutter CLI komutlarını (flutter analyze, build, run) otomatik çalıştırma, kullanıcıya sor.
- `--force` flag kullanma.
