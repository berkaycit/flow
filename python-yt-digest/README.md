# Python YT Digest

Takip edilen YouTube kanallarından bugünün videolarını çekip Claude ile izlenme önceliğine göre triaj eden bir CLI aracı.

## Ne yapar?

- `channels.json`'daki kanalların RSS feed'lerinden bugünün videoları çekilir
- Her videonun İngilizce transkripti `youtube-transcript-api` ile alınır
- Tüm videolar Claude'a gönderilir, İzlenmeli / Belki / Geç olarak sınıflanır
- Daha önce gösterilen videolar `~/.yt_digest_seen.json` ile takip edilir

## Kullanım

```bash
pip install -r requirements.txt
python3 yt_digest.py        # sadece yeni videolar
python3 yt_digest.py --all  # tümü
```

## Kanal Ekleme

`channels.json` dosyasına yeni satır ekleyin:
```json
{"id": "KANAL_ID", "name": "Kanal Adı"}
```

## Gereksinimler

- Python 3.9+
- Claude CLI (`claude -p`)
