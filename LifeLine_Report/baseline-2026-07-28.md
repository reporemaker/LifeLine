# Dependency Report — lifeline
Generated: 2026-07-28 · Scope: full
Ecosystems: none (bash + markdown) · Previous report: none

## Context Map

- **Ekosistem bulunamadı.** `find-manifests.sh` hiçbir MANIFEST / LOCK / CI / CONTAINER /
  LEDGER yüzeyi raporlamadı — proje saf bash + markdown; paket yöneticisi kullanmıyor.
- **Modül yapısı:**
  - `SKILL.md` — skill akışı (giriş noktası)
  - `references/` — ecosystems.md, vendoring.md, report-format.md (talimat verisi, kod değil)
  - `scripts/` — find-manifests.sh, scan-imports.sh, check-vendored.sh (çalışan kod)
- **Modül → dış bağımlılık haritası:**

| Modül | Dış temas |
|---|---|
| scripts/find-manifests.sh | yok (find, sort, awk — sistem araçları) |
| scripts/scan-imports.sh | yok (grep, sed, awk, sort, uniq — sistem araçları) |
| scripts/check-vendored.sh | curl (opsiyonel) → api.osv.dev, api.github.com |

## External Code Inventory

**Paket bağımlılığı: 0.** Bildirilen ve kullanılan hiçbir kayıt-defteri (registry) paketi yok —
README'deki "lifeline itself depends on nothing" iddiası bu denetimle doğrulanmıştır.

Araç zinciri (paket değil, çalışma zamanı gereksinimi):

| Araç | Sürüm koşulu | Zorunlu? | License | Risk signals | Criticality |
|---|---|---|---|---|---|
| bash | ≥ 3.2 (macOS varsayılanıyla test edildi) | evet | GPLv3 (OS bileşeni; kod kopyalanmıyor — lisans kapısını etkilemez) | — | HIGH |
| POSIX/BSD araçları (find, grep, sed, awk, sort, uniq, wc, cut, tr, head) | BSD ve GNU varyantlarıyla uyumlu | evet | OS bileşeni | — | HIGH |
| curl | herhangi | hayır — yoksa OFFLINE moduna düşer, raporda beyan edilir | curl (MIT benzeri) | — | LOW |

Bulgular:

- ⚪ `bash` ve çekirdek Unix araçları her POSIX sistemde mevcuttur; "HIGH" kritiklik teoriktir,
  rehin alma riski taşımaz.
- ⚪ `check-vendored.sh` içindeki ağ erişilebilirlik kapısı tek bir uca (api.osv.dev) bakar;
  OSV erişilemezse GitHub upstream kontrolü de atlanır (bilinçli sadelik — iki servis tek
  NET bayrağını paylaşır).
- ⚪ GitHub API çağrıları kimliksizdir → saatte 60 istek limiti. Çok girdili bir
  VENDORED.md'de limit aşımı `latest=unknown` olarak yansır, hata üretmez.

## External Services

| Service | Referenced in | Credential | If it disappears |
|---|---|---|---|
| api.osv.dev (OSV zafiyet DB) | scripts/check-vendored.sh | hayır | CVE kontrolü yapılamaz; script OFFLINE bildirir, durum `unchecked` olur — sessiz bozulma yok |
| api.github.com (upstream sürüm) | scripts/check-vendored.sh | hayır (kimliksiz) | Upstream güncelleme tespiti `unknown` döner; OSV kontrolü etkilenmez |

İkisi de **opsiyonel zenginleştirme**: skill'in temel işlevi (envanter, harita, rapor) ağ
olmadan tam çalışır — 5 No'lu ilkeyle tutarlı.

## Recommendations

Eylem gerektiren bağımlılık yok. Vendoring adayı yok (dış kod sıfır), phantom dependency yok,
sabitlenecek sürüm yok. İnsan kararı bekleyen tek şey: yok.

## Vendor Tracking

`VENDORED.md` bulunmadı (`NOLEDGER`). Tarama, paket yönetimi dışında içeri kopyalanmış
üçüncü-taraf kod da (yabancı lisans başlığı, vendor-tarzı klasör) tespit etmedi — üç script
ve üç referans dosyasının tamamı özgün içerik. Ledger oluşturmaya gerek yok.

## Limits of This Analysis

- Bash'in import sözdizimi yoktur; kod taraması yalnızca URL yüzeyini kapsar. Script'lerin
  çağırdığı sistem araçları elle, kod okunarak çıkarılmıştır.
- URL taraması `*.md` dosyalarını hariç tutar (doküman linki gürültüsü); SKILL.md ve
  references/ içindeki URL'ler bu yüzden sayımda yoktur — tümü dokümantasyon referansıdır.
- Sistem araçları (bash, curl) için CVE taraması yapılmadı; bunlar işletim sistemi
  güncellemeleriyle yönetilir, proje kapsamı dışındadır.
- Bu denetim ağ erişimi varken çalıştı; OSV bağlantı testi başarılıydı.
