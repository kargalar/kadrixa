# Kadrixa

Uygulama adı **Kadrixa**: fotoğraf ve video kadrajını çağrıştıran kısa bir isim. Android uygulama kimliği ve iOS bundle kimliği **app.kadrixa**. Uygulama içindeki başlık ve kamera seçimi yardım metni aynı adı kullanır.

Simge, koyu `#08090B` zemin üzerinde mercan `#FF626B` diyafram ve açık renkli küçük bir çerçeveden oluşur. Küçük çerçeve, aynı anda iki kamerayla kayıt özelliğini temsil eder. Yazı içermediği için küçük boyutlarda okunaklıdır.

- Kaynak simge: `assets/branding/kadrixa-symbol.png` (şeffaf PNG).
- Mağaza ve paylaşım simgesi: `assets/branding/kadrixa-icon.png` (1024 × 1024, opak RGB).
- Android: beş yoğunluk için eski tip simge, uyarlanabilir ön plan, koyu arka plan ve Android 13 için tek renkli simge katmanı.
- iOS: mevcut AppIcon kataloğundaki tüm boyutlar; alfa kanalı içermez.
- Yeniden boyutlandırma: `dart run tool/generate_brand_icons.dart`.

Simge, yerleşik **image_gen** aracıyla üretildi. Platform boyutları mevcut Dart `image` bağımlılığıyla oluşturulur; yeni bağımlılık eklenmedi.

## Üretim istemi

```text
Use case: logo-brand. Asset type: production mobile camera app launcher icon foreground for the original brand Kadrixa, whose name evokes photographic framing. Generate one standalone polished icon mark on a genuinely transparent square 1024x1024 background, no text or lettering. Mark: a bold circular camera lens / aperture rendered in warm coral (#FF626B), with three broad curved aperture segments surrounding a dark negative-space circular opening; an elegant small rounded viewfinder frame overlaps at the lens upper-right, in soft ivory (#F2F3F5), suggesting simultaneous front and rear video capture. Make the overlaps clean and intentional, one coherent distinctive symbol. Mostly flat precise geometric graphic with a very subtle coral-to-orange highlight for depth, crisp smooth edges, no photorealistic camera hardware, no tiny detail, no drop shadow outside the mark. The central opening and gaps between aperture segments are fully transparent. Strong contrast when placed on near-black #08090B. Center the entire symbol; all artwork contained inside the central 56% of canvas width and height, with generous transparent margins for Android adaptive icon masks. Large readable forms at 48px. No outer app tile, no rounded-square background, no border around the canvas, no checkerboard pattern, no watermark, no multiple variants, no mockups. This image is the final graphic asset, straight-on.
```

Paket kimliği değiştiğinden Android bu sürümü önceki `com.example.camerapro` paketinden ayrı bir uygulama olarak kurar.

Doğrulama: 74 Flutter testi, 5 Android birim testi ve kod analizi geçti; release APK derlendi. APK içindeki ad `Kadrixa`, paket `app.kadrixa`, başlangıç activity'si `app.kadrixa.MainActivity` olarak doğrulandı. Emülatörde kamera başlatıldı, uygulama bilgileri ekranında ad ve uyarlanabilir simge kontrol edildi. iOS simge boyutları, alfa içermeyen PNG çıktıları ve plist kimlikleri doğrulandı; iOS derlemesi Windows ortamında çalıştırılmadı.
