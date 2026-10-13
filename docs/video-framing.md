# Video yönü ve kadrajı

Çekim yönü Android'de fiziksel yön sensöründen alınır; ekranın otomatik döndürme ayarı kaydın yönünü belirlemez. Kayıt başlangıcındaki yön kamera değişimlerinde de korunur. Uygulama ve galeri yatay/dikey ekran düzenini destekler.

Tek kamera önizlemesi, kayıt akışıyla aynı kaynak oranını kullanır. Yüksek çözünürlükte iki büyük kamera yüzeyinin aynı anda açılmasını önlemek için önizleme tamponu en fazla 1080p seçilebilir; kadraj korunur. Oran veya çözünürlük değiştiğinde kamera yeniden hazırlanır. Kaydedilen görüntü, başlangıçta seçilen kadraja merkezden kırpılır ve seçilen çözünürlüğe indirilir. Daha küçük donanım çıktıları büyütülmez. Gerçek çıktı boyutu önizlemede gösterilir. Örneğin 720p'de dikey 4:3 kadraj 720 × 960, yatay 4:3 kadraj 960 × 720, kare kadraj 720 × 720 olur.

Kırpma ve boyutlandırma mevcut kalıcı medya işleme kuyruğunda yapılır. Yön matrisi işleme sırasında görüntüye uygulanır; uygulama kapanırsa iş devam ettirilebilir. Galerideki video küçük resimleri kareye kırpılmadan gösterilir; oynatıcı dosyanın görüntü oranını kullanır.

Doğrulama: 39 Flutter testi, Android yön ve çözünürlük sınıfları için 131 test, kod analizi ve release APK derlemesi. Emülatörde kaydedilen MP4 boyutları, ses/görüntü akışları ve galeri görünümü ayrıca kontrol edilir.

Android kamera geometrisi: https://developer.android.com/media/camera/camera2/camera-preview
