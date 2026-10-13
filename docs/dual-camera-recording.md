# Çift kamera kaydı

Kamera ekranındaki **İKİ KAMERA** modu ön ve arka görüntüyü tek, sesli MP4 dosyasına kaydeder. Ana ekranda seçilen 4:3, 16:9 veya 1:1 oranını kullanır; eşzamanlı kamera modunda çözünürlük en fazla 720p'dir ve gerçek piksel boyutu ekranda gösterilir. Telefon yatay tutulduğunda yatay, dikey tutulduğunda dikey kadraj hazırlanır. Kayıt başlangıcındaki yön kayıt bitene kadar korunur. Küçük görüntü sağ üsttedir. Kamera değiştirme düğmesi kayıt öncesinde ve sırasında ana görüntüyle küçük görüntünün yerini değiştirir; kameraları yeniden açmaz.

Android 11 ve üzerindeki Camera2 `getConcurrentCameraIds` sonucunda ön/arka kamera çifti bulunmalıdır. Bildirilmeyen üretici kamera kimlikleri denenmez. Destek yoksa açıklama gösterilir ve kayıt kapalı tutulur. Bağlı M2101K6G cihazında bu API boş küme döndürdüğünden mod bu cihazda kullanılamıyor. Android dışındaki platformlar için eşzamanlı kayıt henüz uygulanmadı.

`DualCameraController` kameraları ve mikrofonlu MediaRecorder oturumunu yönetir. `DualCameraRenderer` iki SurfaceTexture girişini tek OpenGL karesinde birleştirir; aynı kare önizlemeye ve kayıt yüzeyine gönderilir. Kamera üreticisinin dönüş ve ayna matrisi yalnızca bir kez uygulanır. Kayıt dururken önce yeni kare gönderimi durdurulur, sonra MP4 tamamlanır, ardından kayıt yüzeyi bırakılır. Uygulama arka plana geçtiğinde kayıt tamamlanıp mevcut medya işleme hattıyla galeriye eklenir.

Doğrulama: dört çift kamera widget testi ve mevcut 22 kamera ekranı testi; Android release derlemesi; eşzamanlı `{0, 1}` kamera çiftini bildiren Android emülatöründe önizleme, kayıt içinde yer değiştirme, sesli MP4, galeri kaydı, arka plana geçiş ve geri dönüş. Son test dosyasında görüntü 5,916 saniye, ses 5,909 saniye; arka plana geçiş testinde iki akış yaklaşık 3,5 saniyedir. Fiziksel cihazda desteklenmiyor ekranı ve normal kameraya geri dönüş doğrulandı.

Android destek sözleşmesi: https://source.android.com/docs/core/camera/concurrent-streaming
