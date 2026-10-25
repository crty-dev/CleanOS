# CleanOS

**CleanOS**, Windows 10/11 için PowerShell tabanlı, seçmeli ve geri alınabilir ayar yönetim aracıdır. Varsayılan yaklaşımı “önce göster, sonra onay al” şeklindedir. Defender, Windows Update, güvenlik duvarı, ağ bileşenleri veya Windows'un temel servislerini topluca devre dışı bırakmaz.

- Sürüm: `0.1.0`
- Gereksinim: Windows 10 veya Windows 11, Windows PowerShell 5.1+
- Harici PowerShell modülü: Yok
- Kullanıcı verileri: `%LOCALAPPDATA%\CleanOS`

> **Durum:** Bu, ilk MVP'dir. Windows üzerinde gerçek makinede, sanal makinede ve farklı Windows sürümlerinde test edilmeden üretim kalitesinde olduğu varsayılmamalıdır. Önce test bilgisayarında kullanın.

## Özellikler

1. **Performans:** En yüksek RAM tüketen süreçleri görüntüleme; desteklenen Run kayıt defteri konumlarından başlangıç girdilerini seçerek devre dışı bırakma; mevcut kullanıcı için görsel efekt tercihini performans odaklı ayarlama.
2. **Debloat:** Küçük bir izin listesinde bulunan seçili Appx uygulamalarını yalnızca geçerli kullanıcı profilinden kaldırma. Provisioned paketleri değiştirmez. Uygulama kaldırma işlemi otomatik geri alınabilir değildir.
3. **Gizlilik:** Reklam kimliği, bazı öneri/tanıtım ayarları, tanılama verilerine dayalı kişiselleştirme ve Dosya Gezgini eşitleme bildirimleri için kullanıcı bazlı ayarlar. Gerekli tanılama verilerini tamamen kapatmaz.
4. **Windows Update:** Windows Update sayfalarını açma ve temel güncelleme hizmetlerinin durumunu salt okunur gösterme. Güncelleme hizmetini kapatmaz.
5. **Servis yöneticisi:** Windows servislerinin bir bölümünü salt okunur gösterme; güvenli filtreden geçen bazı üçüncü taraf servislerin başlangıç türünü tek tek ve açık onayla değiştirme. Windows klasöründeki, `svchost.exe` ile çalışan, Microsoft imzalı ve açık koruma listesindeki servisler engellenir.
6. **Geri alma:** Kayıt defteri değişiklikleri ve izin verilen üçüncü taraf servis başlangıç değişiklikleri için işlem günlüğü; eski durumun üzerine sonradan yeni bir tercih yazılmışsa onu ezmemek için değişikliği atlama.
7. **Sürüm denetimi:** GitHub Releases'ta son sürümü kontrol eder. Kendiliğinden kod indirip çalıştırmaz.

## Yerel kullanım

1. Windows PowerShell 5.1 açın.
2. Bu depodaki `CleanOS.ps1` dosyasını indirin veya klonlayın.
3. Dosya içeriklerini inceleyin.
4. Gerektiğinde yönetici PowerShell'den çalıştırın:

```powershell
Set-Location C:\Path\To\CleanOS
.\CleanOS.ps1
```

`irm | iex` kullanmadan önce kaynak kodu incelemek daha güvenlidir. Scriptin tüm özellikleri yönetici izni istemez; kayıt defterinin `HKLM` kapsamındaki başlangıç girdileri ve servis başlangıç türü gibi sistem kapsamlı değişiklikler yükseltilmiş oturum ister.

## Tek komutla çalıştırma (`irm | iex`)

Bu proje henüz senin GitHub hesabında yayımlanmadığından aşağıdaki URL'deki `OWNER` bir yer tutucudur. Gerçek depoyu oluşturup `CleanOS.ps1` dosyasını `main` dalına gönderdikten sonra `OWNER` bölümünü GitHub kullanıcı adın/organizasyonunla değiştir:

```powershell
irm https://raw.githubusercontent.com/crty-dev/CleanOS/main/CleanOS.ps1 | iex
```

Bu komut internetten alınan PowerShell kodunu **doğrudan çalıştırır**. Depo veya yayın hesabı ele geçirilirse indirilen kod da değiştirilebilir. Kullanıcıya dağıtım yapmadan önce sürüm etiketlerini, yayın yetkilerini ve değişiklik incelemesini koruyun. Daha sıkı kontrol isteyenler belirli bir sürüm etiketi kullanabilir:

```powershell
irm https://raw.githubusercontent.com/crty-dev/CleanOS/v0.1.0/CleanOS.ps1 | iex
```

### Yönetici oturumuyla başlatma

HKLM kayıtları veya servis başlangıç türleri gibi yönetici izni gerektiren işlemler için yükseltilmiş PowerShell açıp aynı komutu orada çalıştırın. CleanOS'un içinden yükseltme isteği yapılırsa yeni bir yönetici penceresi açılır; güvenlik nedeniyle işlemi yeni pencerede yeniden seçmeniz gerekir.

## Günlükler ve geri alma

- Geçmiş: `%LOCALAPPDATA%\CleanOS\history\*.json`
- Günlük: `%LOCALAPPDATA%\CleanOS\logs\cleanos.jsonl`

Günlükler yerel diskte kalır; CleanOS telemetri göndermez. İşlem geçmişi, geri alabilmek için önceki bazı kayıt defteri değerlerini ve başlangıç komutlarını içerebilir. Paylaşılan veya kurumsal cihazlarda bu dosyaları hassas veri olarak değerlendirin.

Geri alma yalnızca CleanOS'un takip ettiği değişiklikleri hedefler. Geri alma sırasında işlemden sonra bir ayar elle veya başka bir araçla değiştirilmişse CleanOS daha yeni tercihi ezmemek için bu öğeyi atlar. Appx uygulama kaldırmaları otomatik geri yüklenmez; bu işlemden önce uygulamayı yeniden kurabileceğinizden emin olun.

## Güvenlik sınırları

- Defender, Windows Güvenliği, Windows Update, güvenlik duvarı, DNS, DHCP, ağ profili, RPC, Windows Search ve diğer korumalı servisler topluca kapatılmaz.
- Windows servisleri veya kayıt defteri ayarları adına rastgele “debloat” listeleri çalıştırılmaz.
- Otomatik “her şeyi düzelt” modu yoktur; toplu işlemler kullanıcı onayı ister.
- Windows 10'un standart desteği sona ermiştir. Windows 10 kullanıyorsanız güvenlik güncellemesi/ESU durumunuzu ayrıca kontrol edin.
- CleanOS bir güvenlik ürünü değildir ve Microsoft tarafından desteklenmez.

## Sürüm yayımlama

1. `CleanOS.ps1` içindeki `$script:CleanOSVersion` değerini değiştir.
2. `CHANGELOG.md` içine değişiklikleri ve bilinen sınırlamaları ekle.
3. Scripti Windows PowerShell 5.1 üzerinde analiz et; ilk önce test sanal makinesinde çalıştır.
4. Değişiklikleri inceleyip `vX.Y.Z` etiketi oluştur ve GitHub'a gönder.
5. `.github/workflows/ci.yml` sözdizimi kontrolünü çalıştırır. `release.yml` etiketli sürüm için ZIP ve SHA-256 toplamı yayımlar.
6. Çalıştırma komutunda `main` yerine belirli sürüm etiketini kullanmayı değerlendir.

## Lisans

MIT. Ayrıntılar için `LICENSE` dosyasına bakın.
