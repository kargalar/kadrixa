# Medya Dosyası Adlandırma Tasarımı

## Amaç

Fotoğraf, normal video ve timeburst video kayıtlarının hem uygulamanın kalıcı
depolamasında hem de cihaz galerisinde anlaşılır, tutarlı ve tarih sıralamasına
uygun dosya adları kullanmasını sağlamak.

## Dosya adı biçimleri

- Fotoğraf: `IMG_yyyyMMdd_HHmmss_SSS.jpg`
- Normal video: `VID_yyyyMMdd_HHmmss_SSS.mp4`
- Timeburst video: `TIMELAPSE_yyyyMMdd_HHmmss_SSS.mp4`

Tarih ve saat, kaydın işlenip nihai dosyaya dönüştürüldüğü anda cihazın yerel
saat diliminden alınır. Milisaniye alanı art arda yapılan kayıtların çakışma
olasılığını azaltır. Galeri sağlayıcısı yine de aynı ada rastlarsa platformun
benzersiz ad eki davranışı korunur.

## Tasarım

Flutter tarafında medya türüne göre nihai dosya adını üreten küçük ve bağımsız
bir yardımcı oluşturulacak. Yardımcı, testlerde sabit bir `DateTime` verilebilmesi
için zamanı parametre olarak kabul edecek; üretim kodu verilmediğinde güncel
yerel zamanı kullanacak.

Video ve timeburst çıktı yolları `MediaMuxerService` içinde bu yardımcıyla
oluşturulacak. `gal` paketi kaynak dosyanın adını Android galeri kaydında
koruduğu için uygulama içindeki kalıcı dosya ile cihaz galerisindeki dosya aynı
adı taşıyacak.

Android yerel fotoğraf işleyicisi mevcut tarih-saat tabanlı yaklaşımını koruyacak
ve biçimi `IMG_yyyyMMdd_HHmmss_SSS.jpg` olarak kullanmaya devam edecek. Böylece
fotoğraf ve video adları aynı sözleşmeye uyacak.

## Veri akışı

1. Kamera geçici medya girdisini üretir.
2. Arka plan işleme işi girdiyi kalıcı işleme alanına taşır.
3. Fotoğraf işleyicisi veya video birleştiricisi medya türüne uygun nihai adı
   üretir.
4. Nihai dosya uygulamanın kalıcı medya dizinine yazılır.
5. Aynı dosya cihaz galerisine aktarılır; kaynak adı korunur.
6. Uygulama galerisi nihai kalıcı yolu saklar.

## Hata ve çakışma davranışı

Adlandırma hatası medya işleme hatası olarak mevcut hata akışına iletilir.
FFmpeg, galeri kaydı ve arka plan görevlerinin mevcut hata davranışları
değişmez. Aynı milisaniyede aynı türden iki çıktı oluşursa galeri sağlayıcısının
benzersizleştirme davranışı ikinci kopyanın üzerine yazılmasını engeller.

## Testler

Birim testleri sabit tarihle üç medya türünün tam dosya adını doğrulayacak.
Testler uzantıların ve tür öneklerinin doğru olduğunu ayrı beklentilerle
gösterecek. Uygulama kodu yazılmadan önce bu testlerin eksik ad üreticisi
nedeniyle başarısız olduğu gözlenecek; ardından en küçük uygulama ile
geçmeleri sağlanacak. Son olarak ilgili testler, statik analiz ve mevcut test
paketi çalıştırılacak.

## Kapsam dışı

Kullanıcı tarafından özel dosya adı girilmesi, albüm adının değiştirilmesi,
eski kayıtların yeniden adlandırılması ve galeri ekranında dosya adının
gösterilmesi bu değişikliğin kapsamında değildir.
