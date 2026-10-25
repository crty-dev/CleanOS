# Changelog

## 0.1.0 — 2026-10-25

- İlk MVP: PowerShell menüsü.
- Performans: süreç görüntüleme, başlangıç Run girdilerini seçerek yönetme, görsel efekt tercihi.
- Debloat: izinli listedeki Appx paketlerini mevcut kullanıcı profilinden kaldırma; provisioned paketler hedeflenmez.
- Gizlilik: mevcut kullanıcı için reklam kimliği, içerik önerileri, kişiselleştirme ve eşitleme bildirimi ayarları.
- Windows Update: ayar sayfaları ve salt okunur temel servis durumu.
- Servis yöneticisi: korumalı Windows servislerini engelleyen üçüncü taraf servis başlangıç yönetimi.
- Yerel JSON işlem geçmişi, değişiklik günlüğü ve koşullu geri alma.
- GitHub Releases sürüm denetimi.

### Bilinen sınırlamalar

- İlk sürümdür; henüz gerçek Windows ortamında otomatik test edilmemiştir.
- Appx uygulama kaldırmaları otomatik geri alınamaz.
- Başlangıç yöneticisi yalnızca belirtilen üç Run kayıt defteri konumunu işler; başlangıç klasörlerini ve Görev Zamanlayıcı görevlerini kapsamaz.
- Servis filtresi yanlış pozitif/negatif üretebilir. Emin olunmayan servisleri değiştirmeyin.
- `irm | iex` URL'si gerçek GitHub deposuyla yapılandırılmadan çalışmaz.
