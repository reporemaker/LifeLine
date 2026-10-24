# Dependency Report — lifeline
Generated: 2026-10-24 · Scope: full
Ecosystems: none (bash + markdown) · Previous report: 2026-07-28

## Context Map

- **Ekosistem bulunamadı.** `find-manifests.sh` hiçbir MANIFEST / LOCK / CI / CONTAINER /
  LEDGER yüzeyi raporlamadı — proje saf bash + markdown; paket yöneticisi kullanmıyor.
- **Modül yapısı:**
  - `SKILL.md` — skill akışı (giriş noktası)
  - `references/` — ecosystems.md, vendoring.md, replacements.md, report-format.md (talimat verisi, kod değil)
  - `scripts/` — yedi bash betiği (çalışan kod)
- **Modül → dış bağımlılık haritası:**

| Modül | Dış temas |
|---|---|
| scripts/find-manifests.sh | yok (find, sort — sistem araçları) |
| scripts/scan-imports.sh | yok (grep, sed, awk, sort, uniq) |
| scripts/check-vendored.sh | curl (opsiyonel) → api.osv.dev, api.deps.dev, api.github.com · shasum / sha256sum / openssl (biri) |
| scripts/upstream-health.sh | curl → api.deps.dev, registry.npmjs.org, api.github.com |
| scripts/measure-package.sh | yok · node (opsiyonel, `exports` çözümü için) · python3 (opsiyonel, PyPI paketleri için) |
| scripts/used-api.sh | yok (grep, sed, tr) |
| scripts/upstream-diff.sh | curl → registry.npmjs.org, pypi.org, codeload.github.com, api.github.com · tar, diff |

## External Code Inventory

**Paket bağımlılığı: 0.** Kayıt defterinden (registry) gelen hiçbir paket yok — README'deki
"no dependencies of its own" iddiası bu denetimle yeniden doğrulandı.

Araç zinciri (paket değil, çalışma zamanı gereksinimi):

| Araç | Zorunlu? | Kim kullanıyor | Yoksa |
|---|---|---|---|
| bash ≥ 3.2, find, grep, sed, awk, sort, uniq, wc, cut, tr, head, mktemp | evet | hepsi | — (her POSIX sistemde var) |
| tar, diff | yama yardımı için | upstream-diff.sh | betik hata satırı verir |
| shasum / sha256sum / openssl | yerel değişiklik takibi için | check-vendored.sh | `local=unknown` |
| curl | hayır | ağ kullanan dört betik | `OFFLINE` / `unchecked`, raporda beyan edilir |
| node | hayır | measure-package.sh | `main` alanına düşer; `exports` haritası okunamaz |
| python3 | hayır | measure-package.sh (PyPI) | `NOTFOUND` |

## External Services

| Service | Referenced in | Credential | If it disappears |
|---|---|---|---|
| api.osv.dev | check-vendored.sh | hayır | CVE kontrolü yapılamaz → `unchecked` |
| api.deps.dev | check-vendored.sh, upstream-health.sh | hayır | son sürüm / yayın tarihi / deprecated bilgisi `unknown`; GitHub kaynaklı kayıtlar GitHub'a düşer |
| registry.npmjs.org | upstream-health.sh, upstream-diff.sh | hayır | npm bakımcı sayısı ve kurulum betikleri `unknown`; npm yama farkı alınamaz |
| pypi.org | upstream-diff.sh | hayır | PyPI yama farkı alınamaz |
| api.github.com | check-vendored.sh, upstream-health.sh, upstream-diff.sh | hayır (`GITHUB_TOKEN` opsiyonel) | arşiv bilgisi ve GitHub sürümü `unknown`; saatte 60 istek sınırı |
| codeload.github.com | upstream-diff.sh | hayır | GitHub etiket arşivi indirilemez |

Hepsi **opsiyonel zenginleştirme**: envanter, harita, ölçüm ve rapor ağsız tam çalışır.
Ağ olmadığında hiçbir kontrol "current" sayılmaz.

## Recommendations

Eylem gerektiren bağımlılık yok. Vendoring adayı, yerleşik karşılığı olan paket, hayalet
bağımlılık yok.

## Vendor Tracking

`VENDORED.md` yok (`NOLEDGER`). Paket yönetimi dışında içeri kopyalanmış üçüncü taraf kod
da bulunmadı — betiklerin ve referansların tamamı özgün içerik.

## Changes since last report

- Yeni betikler: upstream-health.sh, measure-package.sh, used-api.sh, upstream-diff.sh.
- Yeni dış servisler (hepsi opsiyonel): api.deps.dev, registry.npmjs.org, pypi.org, codeload.github.com.
- Yeni opsiyonel araçlar: node, python3 (ölçüm); tar, diff (yama); shasum ailesi (checksum).
- Düzeltildi: OSV açıkları eksik sayılıyordu; GitHub dışı kaynaklar kontrol edilmeden
  `current` yazılıyordu; ikili dosyalar ve `.d.ts` import taramasını kirletiyordu.
- Rapor yeri: `docs/` → `LifeLine_Report/`.

## Limits of This Analysis

- Bash'in import sözdizimi yoktur; kod taraması yalnızca URL yüzeyini kapsar. Betiklerin
  çağırdığı sistem araçları elle, kod okunarak çıkarıldı.
- URL taraması `*.md` dosyalarını hariç tutar; SKILL.md ve references/ içindeki
  bağlantılar sayımda yok — tümü dokümantasyon.
- Sistem araçları (bash, curl, tar) için CVE taraması yapılmadı; işletim sistemi
  güncellemeleriyle yönetilirler.
