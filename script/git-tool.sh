#!/bin/bash

# ===============================
# Interactive Git Tool (Ultimate + Status Indicator)
# ===============================

# --- Validasi Git Repo ---
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Direktori ini bukan Git repository"
  exit 1
fi

# --- Validasi fzf ---
if ! command -v fzf >/dev/null 2>&1; then
  echo "❌ Tool ini membutuhkan fzf"
  exit 1
fi

# Pastikan meld terinstal
if ! command -v meld &> /dev/null; then
    echo "Error: 'meld' belum terinstal. Jalankan: sudo apt install meld"
    exit 1
fi

# --- Cek delta ---
if command -v delta >/dev/null 2>&1; then
  USE_DELTA=true
else
  USE_DELTA=false
fi

confirm() {
  read -rp "$1 (ketik YES): " CONFIRM
  [[ "$CONFIRM" == "YES" ]]
}

is_dirty() {
  ! git diff --quiet || ! git diff --cached --quiet
}

# --- Status upstream (pull / push / diverged) ---
upstream_status() {
  UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
  if [ -z "$UPSTREAM" ]; then
    echo "⚠️ No upstream"
    return
  fi

  # FIX: urutan variabel BENAR
  read AHEAD BEHIND <<<$(git rev-list --left-right --count HEAD...@{upstream})

  if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -gt 0 ]; then
    echo "⬇️ $BEHIND | ⬆️ $AHEAD (DIVERGED)"
  elif [ "$BEHIND" -gt 0 ]; then
    echo "⬇️ $BEHIND (PULL)"
  elif [ "$AHEAD" -gt 0 ]; then
    echo "⬆️ $AHEAD (PUSH)"
  else
    echo "✅ Up to date"
  fi
}

while true; do
  clear
  REPO_ROOT=$(git rev-parse --show-toplevel)
  REPO_NAME=$(basename "$REPO_ROOT")
  CURRENT_BRANCH=$(git branch --show-current)

  # --- Hitung Local Changes ---
  # Mengambil jumlah file yang berubah tapi belum di-stage (Modified/Deleted/Untracked)
  UNSTAGED_COUNT=$(git status --porcelain | grep -c "^[ MADRC?][MD?]")
  # Mengambil jumlah file yang sudah di-stage tapi belum di-commit
  STAGED_COUNT=$(git status --porcelain | grep -c "^[MADRC]")

  echo "==============================="
  echo "        GIT TOOL"
  echo "==============================="
  echo "📁 Repo         : $REPO_NAME"
  echo "📌 Branch aktif : $CURRENT_BRANCH"
  echo "🔄 Status       : $(upstream_status)"
  # Tampilkan informasi changes jika ada
  if [ "$UNSTAGED_COUNT" -gt 0 ] || [ "$STAGED_COUNT" -gt 0 ]; then
    echo -n "📝 Changes      : "
    [ "$STAGED_COUNT" -gt 0 ] && echo -ne "\033[1;32m$STAGED_COUNT Staged\033[0m, "
    [ "$UNSTAGED_COUNT" -gt 0 ] && echo -ne "\033[1;31m$UNSTAGED_COUNT Unstaged\033[0m"
    echo ""
  else
    echo "📝 Changes      : ✅ Clean (No changes)"
  fi
  echo

  MENU=$(
    cat <<EOF | fzf --prompt="Pilih menu > " --height=70% --border
🔍  Search & Select Branch (Checkout / Merge)
🌐  Manage Remote
📥  Fetch Remote
⬇️  Pull
⬆️  Push
🏷️  Tag
🕘  History Commit
🌱  Create New Branch
🔗  Set/Change Upstream
📦  Stage & Commit
🗑️  Discard Changes (Undo)
⚖️  Visual Diff (Branch/Folder/File)
🧹  Bulk Delete Branches
🚪  Exit
EOF
  )

  [ -z "$MENU" ] && continue

  case "$MENU" in

  *"Discard Changes (Undo)"*)
    # 1. Ambil daftar file, pastikan ada flag -m agar bisa multi-select
    FILES_TO_DISCARD=$(git status --short | fzf -m \
      --height=60% --border \
      --header=$'\e[33m[TAB]: Tandai | [ENTER]: Lanjut | [CTRL-A]: Select All | [CTRL-D]: Deselect All\e[0m' \
      --prompt="Pilih file untuk Undo > " \
      --pointer="→ " \
      --marker="┃ " \
      --bind "ctrl-a:select-all" \
      --bind "ctrl-d:deselect-all" \
      --preview "
              file=\$(echo {} | awk '{print \$NF}')
              if git diff --cached --quiet -- \"\$file\" 2>/dev/null; then
                  git diff --color=always -- \"\$file\" | sed '1,4d'
              else
                  git diff --cached --color=always -- \"\$file\" | sed '1,4d'
              fi")

    if [ -z "$FILES_TO_DISCARD" ]; then
      echo "🚫 Batal: Tidak ada file yang dipilih."
    else
      CLEAN_FILES=$(echo "$FILES_TO_DISCARD" | awk '{print $NF}')
      
      # Deteksi status untuk pesan peringatan
      has_untracked=$(echo "$FILES_TO_DISCARD" | grep "^??")
      has_staged=$(echo "$FILES_TO_DISCARD" | grep -E "^[^ ]")

      echo -e "\n⚠️  KONFIRMASI PENGHAPUSAN PERMANEN:"
      echo "$CLEAN_FILES" | sed 's/^/  - /'
      echo "------------------------------------------------"

      if [ -n "$has_untracked" ]; then
        echo "🔥 BAHAYA: Daftar mencakup FILE BARU yang akan DIHAPUS FISIK."
      fi

      read -p "Yakin ingin membuang semua perubahan ini? (y/N): " CONFIRM
      if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "🔄 Memproses..."
        
        # Pisahkan file untracked dan tracked
        echo "$FILES_TO_DISCARD" | while read -r line; do
          file=$(echo "$line" | awk '{print $NF}')
          if [[ "$line" == "??"* ]]; then
            # Jika file baru, hapus fisiknya
            rm -rf "$file"
          else
            # Jika file lama, unstage dan undo
            git reset HEAD "$file" &> /dev/null
            git checkout -- "$file"
          fi
        done
        
        echo "✅ Semua perubahan terpilih telah dibersihkan."
      else
        echo "🚫 Dibatalkan."
      fi
    fi
    read -p "Tekan Enter..."
    ;;

  *"Visual Diff (Branch/Folder/File)"*)
    # 1. Pilih Mode Diff
    DIFF_MODE=$(echo -e "📂 Folder / Package Java\n📄 File Spesifik" | fzf --height 40% --reverse --prompt="Pilih Mode > ")
    [ -z "$DIFF_MODE" ] && continue

    # 2. Pilih Branch A (Base)
    BR_A=$(git branch -a | sed 's/^[* ]*//; s/remotes\///' | sort | uniq | fzf --height 40% --reverse --prompt="Pilih Branch A (Base) > ")
    [ -z "$BR_A" ] && continue

    # 3. Pilih Branch B (Target)
    BR_B=$(git branch -a | sed 's/^[* ]*//; s/remotes\///' | sort | uniq | fzf --height 40% --reverse --prompt="Pilih Branch B (Target) > ")
    [ -z "$BR_B" ] && continue

    if [[ "$DIFF_MODE" == *"Folder"* ]]; then
        # 4a. Pilih Folder dengan LOOP
        while true; do
            SEL_FOLDER=$(find . -maxdepth 5 -type d -not -path '*/.*' | fzf \
                --height=80% --border --reverse \
                --prompt="Pilih Folder untuk Diff ($BR_A vs $BR_B) > " \
                --header="ENTER: Buka di Meld | ESC: Kembali ke Menu Utama")

            [ -z "$SEL_FOLDER" ] && break

            # Langsung konfirmasi buka Meld (karena Kompare dihilangkan)
            echo "🚀 Membuka Meld Directory Mode untuk: $SEL_FOLDER"
            
            # -d (directory diff) sangat krusial di sini agar muncul list file di dalam Meld
            git difftool --tool=meld -d "$BR_A" "$BR_B" -- "$SEL_FOLDER"
            
            echo "✅ Selesai review folder. Kembali ke list..."
        done

    elif [[ "$DIFF_MODE" == *"File"* ]]; then
        # 4b. Pilih File dengan LOOP
        while true; do
            SEL_FILE=$(git ls-tree -r "$BR_A" --name-only | fzf \
                --height=80% --border --reverse \
                --prompt="Pilih File ($BR_A vs $BR_B) > " \
                --header="ENTER: Pilih Tool Review | ESC: Kembali ke Menu Utama" \
                --preview "git diff --color=always $BR_A $BR_B -- {1}")

            [ -z "$SEL_FILE" ] && break

            ACTION=$(cat <<EOF | fzf --prompt="Buka '$SEL_FILE' dengan > " --height=25% --reverse --border
1. Visual Meld (Side-by-Side)
3. Terminal View (Fast)
Batal
EOF
            )

            case "$ACTION" in
                *"Meld"*)
                    git difftool --tool=meld --no-prompt "$BR_A" "$BR_B" -- "$SEL_FILE" ;;
                *"Terminal"*)
                    git diff --color=always "$BR_A" "$BR_B" -- "$SEL_FILE" | delta || less -R
                    read -p "Tekan Enter untuk kembali ke list file..." ;;
                *)
                    continue ;;
            esac
        done
    fi

    echo "Kembali ke Menu Utama..."
    sleep 1
    ;;

  *"Bulk Delete Branches"*)
    # 1. Pilih Mode: Lokal atau Remote
    MODE=$(
      cat <<EOF | fzf --height=15% --border --prompt="Pilih Mode Hapus > "
🏠 Local Branches
🌐 Remote Branches
Batal
EOF
    )

    case "$MODE" in
    *"Local"*)
      echo "🔍 Mengambil daftar branch lokal..."
      CURRENT_BR=$(git branch --show-current)
      BRANCHES_TO_DELETE=$(git for-each-ref --format='%(refname:short)' refs/heads/ |
        grep -v "^$CURRENT_BR$" |
        fzf -m --height=60% --border \
          --header="[TAB]: Pilih branch | [ENTER]: Hapus | (Aktif: $CURRENT_BR)" \
          --prompt="Hapus Local > " \
          --marker="❌" --pointer="▶" --color="marker:#ff0000")

      if [ -n "$BRANCHES_TO_DELETE" ]; then
        echo -e "1) Soft (-d)\n2) Force (-D)" | fzf --height=10% --header="Pilih Metode" >/tmp/git_opt
        OPT=$(cat /tmp/git_opt)
        read -p "🔥 Yakin hapus branch lokal tersebut? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          FLAG="-d"
          [[ "$OPT" == *"Force"* ]] && FLAG="-D"
          echo "$BRANCHES_TO_DELETE" | xargs -I {} git branch $FLAG "{}"
          echo "✅ Selesai!"
        fi
      fi
      ;;

    *"Remote"*)
      REMOTE_NAME=$(git remote | fzf --height=20% --prompt="Pilih remote > ")
      [ -z "$REMOTE_NAME" ] && continue

      echo "🔄 Syncing with $REMOTE_NAME..."
      git fetch "$REMOTE_NAME" --prune &>/dev/null

      BRANCHES_TO_DELETE=$(git for-each-ref --format='%(refname:short)' refs/remotes/"$REMOTE_NAME" |
        grep -v "/HEAD$" | sed "s#$REMOTE_NAME/##" |
        fzf -m --height=60% --border \
          --header="[TAB]: Pilih | [ENTER]: Hapus dari Remote" \
          --prompt="Hapus di $REMOTE_NAME > " \
          --marker="❌" --pointer="▶" --color="marker:#ff0000")

      if [ -n "$BRANCHES_TO_DELETE" ]; then
        echo "⚠️  AKAN DIHAPUS DARI REMOTE:"
        echo "$BRANCHES_TO_DELETE" | sed 's/^/  - /'
        read -p "🔥 Yakin hapus PERMANEN di server? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          for br in $BRANCHES_TO_DELETE; do
            git push "$REMOTE_NAME" --delete "$br"
          done
          git fetch "$REMOTE_NAME" --prune &>/dev/null
          echo "✅ Remote cleaned!"
        fi
      fi
      ;;
    esac
    read -p "Tekan Enter..."
    ;;

  *"Stage & Commit"*)
    # Menambahkan opsi bind untuk select-all dan deselect-all
    # Serta header yang menjelaskan shortcut baru
    FILES=$(git status --short | fzf -m --height=60% --border \
      --header=$'\e[33m[TAB]: Tandai | [ENTER]: Commit\n[CTRL+A]: Select All | [CTRL+D]: Deselect All\n[CTRL+R]: Unstage All\e[0m' \
      --pointer="→" \
      --marker="┃" \
      --bind "ctrl-a:select-all" \
      --bind "ctrl-d:deselect-all" \
      --bind "ctrl-r:execute(git reset)+reload(git status --short)" \
      --color="marker:#00ff00,pointer:#ff0000" \
      --preview "
              file=\$(echo {} | gawk '{print \$NF}')
              if git diff --cached --quiet -- \"\$file\" 2>/dev/null; then
                  git diff --color=always -- \"\$file\" | sed '1,4d'
              else
                  git diff --cached --color=always -- \"\$file\" | sed '1,4d'
              fi
              if [[ {} == '??'* ]]; then head -n 100 \"\$file\"; fi
          ")

    # Jika user menekan CTRL-R, list akan reload. Jika setelah itu user tekan ESC/batal:
    if [ -z "$FILES" ]; then
      echo "ℹ️  Keluar dari menu stage."
      sleep 1
      continue
    fi

    # Ambil nama file saja
    CLEAN_FILES=$(echo "$FILES" | gawk '{print $NF}')

    echo "📦 Menyiapkan file:"
    echo "$CLEAN_FILES" | sed 's/^/  - /'

    # Jalankan git add
    echo "$CLEAN_FILES" | xargs git add
    echo "✅ Berhasil di-stage."

    echo ""
    read -p "📝 Masukkan pesan commit (Kosongkan untuk batal): " MSG
    if [ -z "$MSG" ]; then
      echo "🚫 Batal Commit. File tetap di-stage."
    else
      git commit -m "$MSG"

      echo ""
      read -p "🚀 Push ke remote sekarang? (y/N): " PUSH_CONFIRM
      if [[ "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
        REMOTE=$(git remote | fzf --height=20% --prompt="Push ke mana? > ")
        # Pastikan CURRENT_BRANCH terdefinisi, jika belum:
        [ -z "$CURRENT_BRANCH" ] && CURRENT_BRANCH=$(git branch --show-current)
        [ -n "$REMOTE" ] && git push "$REMOTE" "$CURRENT_BRANCH"
      fi
    fi
    read -p "Tekan Enter..."
    ;;

  *"Set/Change Upstream"*)
    echo "🔗 Mengatur Upstream untuk branch: $CURRENT_BRANCH"

    # 1. Ambil daftar remote yang tersedia
    SELECTED_REMOTE=$(git remote | fzf --height=20% --prompt="Pilih remote tujuan > " --border)

    if [ -n "$SELECTED_REMOTE" ]; then
      echo "Mencoba sinkronisasi branch '$CURRENT_BRANCH' ke remote '$SELECTED_REMOTE'..."

      # 2. Jalankan push dengan flag -u (set-upstream)
      if git push -u "$SELECTED_REMOTE" "$CURRENT_BRANCH"; then
        echo "✅ Berhasil! Branch '$CURRENT_BRANCH' sekarang tracking ke '$SELECTED_REMOTE/$CURRENT_BRANCH'."
      else
        echo "❌ Gagal melakukan push/set-upstream."
      fi
    else
      echo "🚫 Batal: Remote tidak dipilih."
    fi

    read -p "Tekan Enter untuk lanjut..."
    ;;

  *"Create New Branch"*)
    echo "🌿 Membuat branch baru dari: $CURRENT_BRANCH"
    read -p "Masukkan nama branch baru (Enter kosong untuk batal): " NEW_BRANCH_NAME

    if [ -z "$NEW_BRANCH_NAME" ]; then
      echo "🚫 Batal membuat branch."
      sleep 1
    else
      # 1. Buat branch baru
      if git checkout -b "$NEW_BRANCH_NAME"; then
        echo "✅ Berhasil pindah ke branch baru: $NEW_BRANCH_NAME"
        CURRENT_BRANCH=$NEW_BRANCH_NAME

        # 2. Opsi untuk langsung set Upstream (Sync ke Remote)
        echo ""
        read -p "❓ Ingin langsung push & set upstream ke remote? (y/N): " push_confirm
        if [[ "$push_confirm" =~ ^[Yy]$ ]]; then

          # 3. Pilih Remote jika ada lebih dari satu
          SELECTED_REMOTE=$(git remote | fzf --height=20% --prompt="Pilih remote tujuan > " --border)

          if [ -n "$SELECTED_REMOTE" ]; then
            echo "🚀 Memulai push ke $SELECTED_REMOTE..."
            # Perintah ini mensinkronkan branch lokal dengan remote
            git push -u "$SELECTED_REMOTE" "$NEW_BRANCH_NAME"
            echo "✅ Branch '$NEW_BRANCH_NAME' sekarang tersinkron dengan '$SELECTED_REMOTE'"
            read -p "Tekan Enter untuk lanjut..."
          else
            echo "⚠️ Remote tidak dipilih, upstream belum di-set."
            sleep 1
          fi
        fi
      else
        echo "❌ Gagal membuat branch."
        read -p "Tekan Enter untuk kembali ke menu..."
      fi
    fi
    ;;

  "🌐  Manage Remote")
    while true; do
      REMOTE_MENU=$(
        cat <<EOF | fzf --prompt="Remote > " --height=40% --border
📋  List Remote
➕  Add Remote
✏️  Rename Remote
🗑️  Delete Remote
📥  Fetch Remote
↩️  Back
EOF
      )
      RET=$?
      [ $RET -ne 0 ] && break
      [ -z "$REMOTE_MENU" ] && break

      case "$REMOTE_MENU" in

      "📋  List Remote")
        git remote |
          fzf --prompt="Remote List > " \
            --preview='
              echo "Remote : {}"
              git remote get-url {} 2>/dev/null
            '
        # ESC otomatis balik ke Manage Remote
        ;;

      "➕  Add Remote")
        read -rp "Nama remote baru (kosong = batal): " REMOTE_NAME
        [ -z "$REMOTE_NAME" ] && continue

        read -rp "URL remote (kosong = batal): " REMOTE_URL
        [ -z "$REMOTE_URL" ] && continue

        git remote add "$REMOTE_NAME" "$REMOTE_URL" &&
          echo "Remote '$REMOTE_NAME' berhasil ditambahkan"

        read -rp "Enter untuk lanjut..."
        ;;

      "✏️  Rename Remote")
        OLD_REMOTE=$(
          git remote |
            fzf --prompt="Pilih remote > " \
              --preview='
                echo "Remote : {}"
                git remote get-url {} 2>/dev/null
              '
        )
        RET=$?
        [ $RET -ne 0 ] && continue
        [ -z "$OLD_REMOTE" ] && continue

        echo "Sedang mengedit remote : $OLD_REMOTE"
        echo "URL                   : $(git remote get-url "$OLD_REMOTE")"

        read -rp "Nama remote baru (kosong = batal): " NEW_REMOTE
        [ -z "$NEW_REMOTE" ] && continue

        git remote rename "$OLD_REMOTE" "$NEW_REMOTE" &&
          echo "Remote '$OLD_REMOTE' → '$NEW_REMOTE'"

        read -rp "Enter untuk lanjut..."
        ;;

      "🗑️  Delete Remote")
        DEL_REMOTE=$(
          git remote |
            fzf --prompt="Hapus remote > " \
              --preview='
                echo "Remote : {}"
                git remote get-url {} 2>/dev/null
              '
        )
        RET=$?
        [ $RET -ne 0 ] && continue
        [ -z "$DEL_REMOTE" ] && continue

        read -rp "Yakin hapus remote '$DEL_REMOTE'? [y/N] " CONFIRM
        [[ "$CONFIRM" =~ ^[Yy]$ ]] || continue

        git remote remove "$DEL_REMOTE" &&
          echo "Remote '$DEL_REMOTE' dihapus"

        read -rp "Enter untuk lanjut..."
        ;;

      "📥  Fetch Remote")
        FETCH_REMOTE=$(
          git remote |
            fzf --prompt="Fetch remote > " \
              --preview='
                echo "Remote : {}"
                git remote get-url {} 2>/dev/null
              '
        )
        RET=$?
        [ $RET -ne 0 ] && continue
        [ -z "$FETCH_REMOTE" ] && continue

        git fetch "$FETCH_REMOTE"
        read -rp "Enter untuk lanjut..."
        ;;

      "↩️  Back")
        break
        ;;

      esac
    done
    ;;

  # ================= PULL =================
  *Pull*)
    REMOTE=$(git remote | fzf --prompt="Pilih remote untuk pull > ")
    [ -z "$REMOTE" ] && continue

    PULL_MODE=$(
      cat <<EOF | fzf --prompt="Pull mode ($REMOTE/$CURRENT_BRANCH) > "
Pull (merge)
Pull (rebase)
Pull (HARD RESET)
Batal
EOF
    )

    case "$PULL_MODE" in
    *HARD*)
      confirm "HARD RESET ke $REMOTE/$CURRENT_BRANCH?" || continue
      git fetch "$REMOTE" &&
        git reset --hard "$REMOTE/$CURRENT_BRANCH"
      read -rp "ENTER untuk lanjut..."
      ;;
    *merge* | *rebase*)
      if is_dirty; then
        DIRTY_ACTION=$(
          cat <<EOF | fzf --prompt="Working tree kotor > "
Stash lalu pull
Force reset lalu pull
Batal
EOF
        )
        case "$DIRTY_ACTION" in
        *Stash*) git stash push -u -m "auto-stash before pull" ;;
        *Force*)
          confirm "Reset hard sebelum pull?" || continue
          git reset --hard
          ;;
        *) continue ;;
        esac
      fi

      if [[ "$PULL_MODE" == *rebase* ]]; then
        git pull --rebase "$REMOTE" "$CURRENT_BRANCH"
      else
        git pull "$REMOTE" "$CURRENT_BRANCH"
      fi
      read -rp "ENTER untuk lanjut..."
      ;;
    esac
    ;;

  # ================= PUSH =================
  *Push*)
    REMOTE=$(git remote | fzf --prompt="Pilih remote > ")
    [ -z "$REMOTE" ] && continue

    PUSH_ACTION=$(
      cat <<EOF | fzf --prompt="Push ke '$REMOTE' > "
Push branch aktif
Push semua branch
Push semua tag
Batal
EOF
    )

    case "$PUSH_ACTION" in
    *aktif*) git push "$REMOTE" "$CURRENT_BRANCH" ;;
    *semua\ branch*) git push "$REMOTE" --all ;;
    *semua\ tag*) git push "$REMOTE" --tags ;;
    esac
    read -rp "ENTER..."
    ;;

  # ================= TAG =================
  *Tag*)
    while true; do
      TAG_MENU=$(
        cat <<EOF | fzf --prompt="Tag menu > "
Create Tag
List Tag
Kembali
EOF
      )
      case "$TAG_MENU" in
      *Create*)
        read -rp "Nama tag: " TAG_NAME
        [ -z "$TAG_NAME" ] && continue
        git rev-parse "$TAG_NAME" >/dev/null 2>&1 && {
          echo "❌ Tag sudah ada"
          read -rp "ENTER..."
          continue
        }
        read -rp "Message tag (kosong = lightweight): " TAG_MSG
        [ -z "$TAG_MSG" ] && git tag "$TAG_NAME" || git tag -a "$TAG_NAME" -m "$TAG_MSG"
        read -rp "ENTER..."
        ;;
      *List*)
        while true; do
          TAG=$(git tag --sort=-creatordate | fzf --prompt="Pilih tag > ")
          [ -z "$TAG" ] && break
          TAG_ACTION=$(
            cat <<EOF | fzf --prompt="Aksi tag '$TAG' > "
Push tag ke remote
Delete tag
Lihat detail tag
Kembali
EOF
          )
          case "$TAG_ACTION" in
          *Push*)
            REMOTE=$(git remote | fzf --prompt="Remote > ")
            [ -z "$REMOTE" ] || git push "$REMOTE" "$TAG"
            ;;
          *Delete*)
            OPT=$(
              cat <<EOF | fzf --prompt="Delete '$TAG' > "
Delete tag LOCAL
Delete tag REMOTE
Batal
EOF
            )
            case "$OPT" in
            *LOCAL*) confirm "Delete tag local?" && git tag -d "$TAG" ;;
            *REMOTE*)
              REMOTE=$(git remote | fzf --prompt="Remote > ")
              [ -z "$REMOTE" ] || confirm "Delete tag remote?" &&
                git push "$REMOTE" ":refs/tags/$TAG"
              ;;
            esac
            ;;
          *Detail*) git show "$TAG" | less -R ;;
          esac
        done
        ;;
      *) break ;;
      esac
    done
    ;;

  # ================= FETCH =================
  *"Fetch Remote"*)
    # 1. Pilih Remote dulu (Default & Utama)
    REMOTE=$(git remote | fzf --prompt="Pilih remote tujuan > " --height=20% --border)

    # Cek jika user membatalkan pilihan remote
    if [ -z "$REMOTE" ]; then
      echo "🚫 Batal: Tidak ada remote yang dipilih."
    else
      # 2. Setelah remote terpilih, baru pilih aksinya
      ACTION=$(
        cat <<EOF | fzf --prompt="Aksi Fetch untuk '$REMOTE' > " --height=15% --border
Fetch Normal
Fetch & Prune (Bersihkan branch mati)
Batal
EOF
      )

      case "$ACTION" in
      *"Fetch Normal"*)
        echo "📥 Fetching dari $REMOTE..."
        git fetch "$REMOTE"
        ;;

      *"Fetch & Prune"*)
        echo "🧹 Fetching & Pruning dari $REMOTE..."
        # Hanya melakukan prune pada remote yang dipilih
        git fetch "$REMOTE" --prune
        echo "✅ Selesai: Branch mati di remote '$REMOTE' sudah dibersihkan dari list lokal."
        ;;

      *)
        echo "🚫 Batal."
        ;;
      esac
    fi

    read -rp "Tekan Enter untuk lanjut..."
    ;;

  # ================= SEARCH BRANCH =================
  *Search*)
    # List branch local & remote, bersihkan tampilan
    SELECTED_BRANCH=$(git branch -a | sed 's/^[* ] //' | sed 's#remotes/##' | sort -u | fzf)

    [ -z "$SELECTED_BRANCH" ] && continue

    ACTION=$(
      cat <<EOF | fzf --prompt="Aksi untuk '$SELECTED_BRANCH' > "
Checkout ke LOCAL
Merge ke branch aktif ($CURRENT_BRANCH)
Hapus Branch LOCAL (Force)
Hapus Branch REMOTE
Batal
EOF
    )

    case "$ACTION" in
    *Checkout*)
      if git show-ref --verify --quiet "refs/heads/$SELECTED_BRANCH"; then
        git switch "$SELECTED_BRANCH"
      else
        # Handle checkout dari remote ref (misal: origin/feature)
        REMOTE_NAME=$(cut -d/ -f1 <<<"$SELECTED_BRANCH")
        BRANCH_NAME=$(cut -d/ -f2- <<<"$SELECTED_BRANCH")
        git switch -c "$BRANCH_NAME" "$REMOTE_NAME/$BRANCH_NAME"
      fi
      ;;

    *Merge*)
  echo "🔄 Mencoba menggabungkan '$SELECTED_BRANCH' ke '$CURRENT_BRANCH'..."

  if git merge "$SELECTED_BRANCH"; then
    echo "✅ Berhasil digabungkan tanpa konflik."
    read -p "↩️  Tekan Enter untuk kembali ke menu utama..." _
  else
    echo "⚠️  Terjadi KONFLIK!"

    RESOLVE_TOOL=$(cat <<EOF | fzf --prompt="Pilih cara resolve conflict > " --height=40% --border
🔥 Sublime Merge (recommended)
🧠 IntelliJ IDEA
🧩 Meld
🕒 Later (manual resolve)
EOF
)

    case "$RESOLVE_TOOL" in
      *Sublime*)
        echo "🚀 Membuka Sublime Merge..."
        git config --local merge.tool smerge
        git config --local mergetool.prompt false
        git mergetool
        ;;
      *IntelliJ*)
        echo "🚀 Membuka IntelliJ IDEA..."
        git config --local merge.tool idea
        git config --local mergetool.prompt false
        git mergetool
        ;;
      *Meld*)
        echo "🚀 Membuka Meld..."
        git config --local merge.tool meld
        git config --local mergetool.prompt false
        git mergetool
        ;;
      *)
        echo "🕒 Resolve ditunda."
        echo "   Kamu masih dalam state MERGING."
        echo
        echo "   Opsi yang bisa kamu lakukan:"
        echo "     - git status"
        echo "     - git mergetool"
        echo "     - git merge --abort"
        read -p "↩️  Tekan Enter untuk kembali ke menu utama..." _
        continue
        ;;
    esac

    # === CEK APAKAH MASIH ADA KONFLIK ===
    if git diff --name-only --diff-filter=U | grep -q .; then
      echo
      echo "❌ Masih ada konflik yang belum diselesaikan."
      echo "   Selesaikan dulu sebelum commit."
      read -p "↩️  Tekan Enter untuk kembali ke menu utama..." _
      continue
    fi

    echo
    echo "📝 Semua konflik berhasil diselesaikan."
    read -p "Lanjutkan commit merge sekarang? (y/n): " do_commit
    if [[ "$do_commit" =~ ^[Yy]$ ]]; then
      git commit --no-edit
      echo "✅ Merge selesai dan sudah di-commit."
    else
      echo "ℹ️  Merge siap, tapi belum di-commit."
      echo "   Kamu bisa commit nanti lewat menu Stage & Commit."
    fi

    read -p "↩️  Tekan Enter untuk kembali ke menu utama..." _
  fi
  ;;


    *Hapus*LOCAL*)
      # Konfirmasi sebelum hapus local
      read -p "🗑️  Yakin hapus branch LOCAL '$SELECTED_BRANCH'? (y/N) " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Menggunakan -D (Force Delete) untuk memastikan terhapus meski belum di-merge
        git branch -D "$SELECTED_BRANCH"
      else
        echo "Dibatalkan."
      fi
      ;;

    *Hapus*REMOTE*)
      # Cek apakah string branch memiliki format 'remote/branch'
      if [[ "$SELECTED_BRANCH" == *"/"* ]]; then
        REMOTE_NAME=$(cut -d/ -f1 <<<"$SELECTED_BRANCH")
        BRANCH_NAME=$(cut -d/ -f2- <<<"$SELECTED_BRANCH")

        read -p "⚠️  BAHAYA: Yakin hapus branch REMOTE '$REMOTE_NAME' -> '$BRANCH_NAME'? (y/N) " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          git push "$REMOTE_NAME" --delete "$BRANCH_NAME"
        else
          echo "Dibatalkan."
        fi
      else
        echo "❌ Error: '$SELECTED_BRANCH' sepertinya bukan remote branch (tidak ada remote prefix)."
        read -p "Tekan Enter untuk lanjut..."
      fi
      ;;
    esac
    ;;

  # ================= HISTORY COMMIT =================
  *History\ Commit*)
    while true; do
      # 1. Identifikasi commit yang belum di-push (Lokal saja)
      # git cherry memberikan list hash dengan tanda '+' untuk yang belum di-push
      LOCAL_COMMITS=$(git cherry -v 2>/dev/null | gawk '{print $2}')

      # 2. Pilih Commit
      COMMIT_LINE=$(
        git log --first-parent \
          --date=format:'%Y-%m-%d %H:%M' \
          --pretty=format:'%h|%ad|%an|%p|%s' \
          --shortstat |
          gawk -v local_list="$LOCAL_COMMITS" '
        BEGIN {
          hash=""; date=""; author=""; parents=""; subject="";
          added=0; deleted=0;
          split(local_list, locals, " ");
          for (i in locals) local_map[locals[i]] = 1;
        }
        /^[0-9a-f]+\|/ {
          if (hash != "") {
            type_icon = (split(parents,p," ") > 1) ? "🔀" : "✨"
            loc_tag = (hash in local_map) ? " \033[1;33m[L]\033[0m" : "    "
            printf "%-8s%s 🗓 %-16s 👤 %-10s %s ➕%-4d ➖%-4d %s\n",
                  hash, loc_tag, date, author, type_icon, added, deleted, subject
          }
          split($0, a, "|")
          hash=a[1]; date=a[2]; author=a[3]; parents=a[4]; subject=a[5]
          added=0; deleted=0
          next
        }
        /insertions?/ { match($0, /([0-9]+) insertion/, m); if (m[1] != "") added=m[1] }
        /deletions?/ { match($0, /([0-9]+) deletion/, m); if (m[1] != "") deleted=m[1] }
        END {
          if (hash != "") {
            type_icon = (split(parents,p," ") > 1) ? "🔀" : "✨"
            loc_tag = (hash in local_map) ? " \033[1;33m[L]\033[0m" : "    "
            printf "%-8s%s 🗓 %-16s 👤 %-10s %s ➕%-4d ➖%-4d %s\n",
                  hash, loc_tag, date, author, type_icon, added, deleted, subject
          }
        }
      ' | fzf --ansi --prompt="Cari di Branch $CURRENT_BRANCH > " \
          --height=60% --border \
          --header="Ketik untuk mencari commit lama" \
          --preview "git show --color=always {1} | head -200"
      )

      [ -z "$COMMIT_LINE" ] && break

      COMMIT_HASH=$(gawk '{print $1}' <<<"$COMMIT_LINE")
      COMMIT_SUBJ=$(cut -d' ' -f9- <<<"$COMMIT_LINE") # Geser f9 karena ada kolom [L]

      # Cek apakah commit ini bagian dari Local Commits
      IS_LOCAL=$(echo "$LOCAL_COMMITS" | grep "$COMMIT_HASH")

      # 3. Buat Menu Aksi secara dinamis
      MENU_OPTIONS="🔍 Lihat List File (Diff)\n"
      if [ -n "$IS_LOCAL" ]; then
        MENU_OPTIONS+="📝 Edit Commit Message (Local)\n"
      fi
      MENU_OPTIONS+="🧹 Reset Mixed\n"
      MENU_OPTIONS+="🔥 Reset Hard\n"
      MENU_OPTIONS+="Batal"

      ACTION=$(echo -e "$MENU_OPTIONS" | fzf --prompt="Aksi untuk [$COMMIT_HASH] > " --height=20% --border --header="Commit: $COMMIT_SUBJ")

      case "$ACTION" in
      *"Lihat List File"*)
    PARENT_COUNT=$(git cat-file -p "$COMMIT_HASH" | grep '^parent ' | wc -l)
    BASE_COMMIT=$([ "$PARENT_COUNT" -gt 1 ] && echo "$COMMIT_HASH^1" || echo "$COMMIT_HASH^")

    FILE_LIST=$(git diff --name-only "$BASE_COMMIT" "$COMMIT_HASH")

    while true; do
        FILE_PATH=$(echo "$FILE_LIST" | fzf \
            --prompt="Pilih File untuk Review > " \
            --height=80% --border \
            --preview "git diff --color=always $BASE_COMMIT $COMMIT_HASH -- {1} | sed '1,4d'")

        [ -z "$FILE_PATH" ] && break

        # Sub-menu untuk memilih tool (3 Opsi)
        ACTION=$(cat <<EOF | fzf --prompt="Buka '$FILE_PATH' dengan > " --height=25% --reverse --border
1. Visual Meld (3-Way/Side-by-Side)
2. Visual Kompare (KDE Native)
3. Terminal View (Fast)
Batal
EOF
        )

        case "$ACTION" in
            *"Meld"*)
                echo "🚀 Membuka Meld..."
                git difftool --tool=meld --no-prompt "$BASE_COMMIT" "$COMMIT_HASH" -- "$FILE_PATH"
                ;;
            *"Kompare"*)
                echo "🎨 Membuka Kompare..."
                # Memastikan kompare dipanggil sebagai tool
                git difftool --tool=kompare --no-prompt "$BASE_COMMIT" "$COMMIT_HASH" -- "$FILE_PATH"
                ;;
            *"Terminal"*)
                echo "📄 Menampilkan di Terminal..."
                if [ "$USE_DELTA" = true ]; then
                    git diff --color=always "$BASE_COMMIT" "$COMMIT_HASH" -- "$FILE_PATH" | delta
                else
                    git diff --color=always "$BASE_COMMIT" "$COMMIT_HASH" -- "$FILE_PATH" | less -R
                fi
                read -p "Tekan Enter untuk kembali..."
                ;;
            *)
                continue
                ;;
        esac
    done
    ;;

      *"Edit Commit Message"*)
        LATEST_HASH=$(git rev-parse --short HEAD)
        if [ "$COMMIT_HASH" == "$LATEST_HASH" ]; then
          git commit --amend
        else
          echo "💡 Rebase interaktif untuk commit lama..."
          sleep 2
          git rebase -i "$COMMIT_HASH^"
        fi
        ;;

      *"Reset Mixed"*)
        git reset --mixed "$COMMIT_HASH"
        echo "✅ Reset Mixed berhasil."
        read -p "Enter..."
        break
        ;;

      *"Reset Hard"*)
        read -p "⚠️  HAPUS PERMANEN semua perubahan ke $COMMIT_HASH? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          git reset --hard "$COMMIT_HASH"
          read -p "Enter..."
          break
        fi
        ;;
      esac
    done
    ;;

  "🚪  Exit")
    break
    ;;
  esac
done
