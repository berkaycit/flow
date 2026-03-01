# Python HN Digest

Hacker News front page ve günün hikayelerini çekip Claude ile önem sırasına göre triaj eden bir CLI aracı.

## Ne yapar?

- Algolia HN API üzerinden front page (30) ve bugünün hikayeleri (30) çekilir
- Merge + dedup sonrası tüm havuz Claude'a gönderilir
- Claude hikayeleri Yüksek / Orta / Düşük olarak sınıflar ve özetler
- Daha önce gösterilen hikayeler `~/.hn_digest_seen.json` ile takip edilir

## Kullanım

```bash
pip install -r requirements.txt
python3 hn_digest.py        # sadece yeni hikayeler
python3 hn_digest.py --all  # tümü
```

## Gereksinimler

- Python 3.9+
- Claude CLI (`claude -p`)
