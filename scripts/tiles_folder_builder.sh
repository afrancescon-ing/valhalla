#!/bin/bash

# Script per processare mappe personalizzate con Valhalla
# Basato sul Dockerfile.extended originale ma con supporto per mappe generiche

set -e  # Exit on any error

# Configurazione di default
WORK_DIR="/valhalla_tiles"
CONFIG_FILE="valhalla.json"
TRAFFIC_ENABLED=true
CLEANUP_SOURCE=false
CONCURRENCY=${CONCURRENCY:-$(nproc)}
UPDATE_TRAFFIC_PY_FILE="/usr/local/src/valhalla/scripts/update_traffic.py"

# Funzione di help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] [MAP_SOURCE]

Process a custom map with Valhalla routing engine.

MAP_SOURCE (opzionale) può essere:
  - URL di un file .osm.pbf (es: https://download.geofabrik.de/europe/italy-latest.osm.pbf)
  - Percorso locale a un file .osm.pbf
  - Nome di una regione Geofabrik (es: italy, germany, france)
  
Se MAP_SOURCE non è specificato:
  - Cerca file .osm.pbf nella WORK_DIR
  - Se non trovato, cerca in WORK_DIR/default_map/
  - Errore se trovati 0 o più di 1 file

OPTIONS:
  -d, --work-dir DIR        Directory di lavoro (default: $WORK_DIR)
  -c, --config FILE        Nome del file di configurazione (default: $CONFIG_FILE)
  -t, --enable-traffic      Abilita supporto traffico
  -r, --remove-source       Rimuovi il file sorgente .osm.pbf dopo il processing
  -j, --jobs NUM           Numero di job paralleli (default: auto-detect)
  -h, --help               Mostra questo aiuto

Examples:
  $0                       # Usa file .osm.pbf nella WORK_DIR o default_map/
  $0 italy
  $0 https://download.geofabrik.de/europe/italy-latest.osm.pbf
  $0 /path/to/custom.osm.pbf --enable-traffic
  $0 germany --work-dir /custom/path --jobs 8
EOF
}

# Parsing degli argomenti
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -t|--enable-traffic)
            TRAFFIC_ENABLED=true
            shift
            ;;
        -r|--remove-source)
            CLEANUP_SOURCE=true
            shift
            ;;
        -j|--jobs)
            CONCURRENCY="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "Opzione sconosciuta: $1" >&2
            show_help
            exit 1
            ;;
        *)
            if [[ -z "${MAP_SOURCE:-}" ]]; then
                MAP_SOURCE="$1"
            else
                echo "Troppi argomenti posizionali" >&2
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Verifica che MAP_SOURCE sia specificato o auto-rilevabile
if [[ -z "${MAP_SOURCE:-}" ]]; then
    echo "🔍 Nessuna mappa specificata, ricerca automatica..."
    MAP_SOURCE=$(auto_detect_map_source "$WORK_DIR")
fi

# Funzione per auto-rilevare la mappa sorgente
auto_detect_map_source() {
    local work_dir="$1"
    
    # Prima ricerca nella WORK_DIR
    local pbf_files=($(find "$work_dir" -maxdepth 1 -name "*.osm.pbf" 2>/dev/null))
    
    if [[ ${#pbf_files[@]} -eq 1 ]]; then
        echo "✅ Trovato file mappa: ${pbf_files[0]}"
        echo "${pbf_files[0]}"
        return 0
    elif [[ ${#pbf_files[@]} -gt 1 ]]; then
        echo "❌ Errore: Trovati più file .osm.pbf nella directory $work_dir" >&2
        echo "File disponibili:" >&2
        printf '  - %s\n' "${pbf_files[@]}" >&2
        echo "Specifica quale file utilizzare come argomento." >&2
        exit 1
    fi
    
    # Se non trovato, cerca in default_map/
    local default_dir="${work_dir}/default_map"
    if [[ -d "$default_dir" ]]; then
        local default_files=($(find "$default_dir" -maxdepth 1 -name "*.osm.pbf" 2>/dev/null))
        
        if [[ ${#default_files[@]} -eq 1 ]]; then
            echo "✅ Trovato file mappa di default: ${default_files[0]}"
            echo "${default_files[0]}"
            return 0
        elif [[ ${#default_files[@]} -gt 1 ]]; then
            echo "❌ Errore: Trovati più file .osm.pbf nella directory $default_dir" >&2
            echo "File disponibili:" >&2
            printf '  - %s\n' "${default_files[@]}" >&2
            echo "Specifica quale file utilizzare come argomento." >&2
            exit 1
        fi
    fi
    
    # Nessun file trovato
    echo "❌ Errore: Nessun file .osm.pbf trovato" >&2
    echo "Cercato in:" >&2
    echo "  - $work_dir/*.osm.pbf" >&2
    echo "  - $default_dir/*.osm.pbf" >&2
    echo "" >&2
    echo "Soluzioni:" >&2
    echo "  1. Specifica una mappa come argomento (es: $0 italy)" >&2
    echo "  2. Posiziona un file .osm.pbf in $work_dir/" >&2
    echo "  3. Posiziona un file .osm.pbf in $default_dir/" >&2
    exit 1
}

# Funzione per determinare il nome del file dalla fonte
get_filename_from_source() {
    local source="$1"
    
    if [[ "$source" =~ ^https?:// ]]; then
        # È un URL - estrai il nome del file
        basename "$source"
    elif [[ -f "$source" ]]; then
        # È un file locale - usa il nome del file
        basename "$source"
    else
        # Assume che sia un nome di regione Geofabrik
        echo "${source}-latest.osm.pbf"
    fi
}

# Funzione per scaricare/copiare il file sorgente
prepare_source_file() {
    local source="$1"
    local target_file="$2"
    
    echo "📥 Preparazione file sorgente..."
    
    if [[ "$source" =~ ^https?:// ]]; then
        echo "Scaricamento da URL: $source"
        wget --no-check-certificate --progress=bar:force "$source" -O "$target_file"
    elif [[ -f "$source" ]]; then
        echo "Copia da file locale: $source"
        cp "$source" "$target_file"
    else
        # Assume che sia un nome di regione Geofabrik
        local geofabrik_url="https://download.geofabrik.de/europe/${source}-latest.osm.pbf"
        echo "Scaricamento regione Geofabrik: $geofabrik_url"
        wget --no-check-certificate --progress=bar:force "$geofabrik_url" -O "$target_file"
    fi
    
    if [[ ! -f "$target_file" ]]; then
        echo "❌ Errore: Impossibile ottenere il file sorgente" >&2
        exit 1
    fi
    
    echo "✅ File sorgente preparato: $target_file"
}

# Funzione per generare la configurazione
generate_config() {
    local work_dir="$1"
    local config_file="$2"
    local traffic_enabled="$3"
    
    echo "⚙️  Generazione configurazione Valhalla..."
    
    local traffic_option=""
    if [[ "$traffic_enabled" == "true" ]]; then
        traffic_option="--mjolnir-traffic-extract ${work_dir}/traffic.tar"
    fi
    
    valhalla_build_config \
        --mjolnir-tile-dir "${work_dir}/valhalla_tiles" \
        --mjolnir-timezone "${work_dir}/valhalla_tiles/timezones.sqlite" \
        --mjolnir-admin "${work_dir}/valhalla_tiles/admins.sqlite" \
        $traffic_option \
        > "${work_dir}/valhalla_raw.json"
    
    # Rimuovi opzioni non utilizzate per mantenere pulito l'output del servizio
    sed -e '/elevation/d' -e '/tile_extract/d' "${work_dir}/valhalla_raw.json" > "${work_dir}/${config_file}"
    
    echo "✅ Configurazione generata: ${work_dir}/${config_file}"
}

# Funzione per costruire i tile
build_tiles() {
    local work_dir="$1"
    local config_file="$2"
    local source_file="$3"
    local concurrency="$4"
    
    echo "🔨 Costruzione tile di routing..."
    echo "Utilizzando $concurrency job paralleli"
    
    cd "$work_dir"
    valhalla_build_tiles -j "$concurrency" -c "$config_file" "$source_file"
    
    echo "📦 Creazione archivio tile..."
    find valhalla_tiles | sort -n | tar cf valhalla_tiles.tar --no-recursion -T -
    
    echo "✅ Tile di routing costruiti"
}

# Funzione per configurare il traffico
setup_traffic() {
    local work_dir="$1"
    local config_file="$2"
    
    echo "🚦 Configurazione supporto traffico..."
    
    cd "$work_dir"
    
    # Crea struttura directory per i dati del traffico
    mkdir -p traffic
    cd valhalla_tiles
    find . -type d -exec mkdir -p -- ../traffic/{} \;
    cd ..
    
    # Genera mappatura OSM ways -> Valhalla edges
    echo "🗺️  Generazione mappatura OSM ways -> Valhalla edges..."
    valhalla_ways_to_edges --config "$config_file"

    # Copia lo script update_traffic.py in traffic
    cp $UPDATE_TRAFFIC_PY_FILE traffic/update_traffic.py

    
    echo "✅ Supporto traffico configurato"
    echo "📝 File mappatura disponibile in: ${work_dir}/way_edges.txt"
    echo "📁 Directory traffico: ${work_dir}/traffic/"
}

# Funzione principale
main() {
    echo "🚀 Avvio processamento mappa personalizzata"
    
    if [[ "$MAP_SOURCE" == /* ]] && [[ -f "$MAP_SOURCE" ]]; then
        echo "📍 Sorgente: File locale - $MAP_SOURCE"
    else
        echo "📍 Sorgente: $MAP_SOURCE"
    fi
    
    echo "📂 Directory lavoro: $WORK_DIR"
    echo "⚙️  File configurazione: $CONFIG_FILE"
    echo "🚦 Traffico abilitato: $TRAFFIC_ENABLED"
    echo "🧹 Rimozione sorgente: $CLEANUP_SOURCE"
    echo "⚡ Concorrenza: $CONCURRENCY job"
    echo ""
    
    # Prepara la directory di lavoro
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    # Determina il nome del file e gestisci file già esistenti
    local filename
    local source_file
    local needs_download=true
    
    # Se MAP_SOURCE è un file locale esistente, usalo direttamente
    if [[ -f "$MAP_SOURCE" ]]; then
        source_file="$MAP_SOURCE"
        filename=$(basename "$MAP_SOURCE")
        needs_download=false
        echo "📁 Utilizzo file locale esistente: $source_file"
    else
        filename=$(get_filename_from_source "$MAP_SOURCE")
        source_file="${WORK_DIR}/${filename}"
        
        # Controlla se il file esiste già nella WORK_DIR
        if [[ -f "$source_file" ]]; then
            echo "📁 File già presente in WORK_DIR: $source_file"
            read -p "Vuoi utilizzare il file esistente? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                needs_download=false
            else
                echo "🔄 Il file esistente verrà sovrascritto..."
            fi
        fi
    fi
    
    # Scarica/prepara il file solo se necessario
    if [[ "$needs_download" == "true" ]]; then
        prepare_source_file "$MAP_SOURCE" "$source_file"
    fi
    
    # Genera la configurazione
    generate_config "$WORK_DIR" "$CONFIG_FILE" "$TRAFFIC_ENABLED"
    
    # Costruisci i tile
    build_tiles "$WORK_DIR" "$CONFIG_FILE" "$filename" "$CONCURRENCY"
    
    # Configura il traffico se richiesto
    if [[ "$TRAFFIC_ENABLED" == "true" ]]; then
        setup_traffic "$WORK_DIR" "$CONFIG_FILE"
    fi
    
    # Pulizia opzionale
    if [[ "$CLEANUP_SOURCE" == "true" ]]; then
        # Non rimuovere il file se era già esistente nella posizione originale
        if [[ "$source_file" != "$MAP_SOURCE" ]] || [[ "$needs_download" == "true" ]]; then
            echo "🧹 Rimozione file sorgente: $source_file"
            rm -f "$source_file"
        else
            echo "ℹ️  File sorgente mantenuto (era già presente): $source_file"
        fi
    else
        echo "📁 File sorgente mantenuto: $source_file"
    fi
    
    echo ""
    echo "🎉 Processamento completato con successo!"
    echo "📁 Dati disponibili in: $WORK_DIR"
    echo "⚙️  Configurazione: ${WORK_DIR}/${CONFIG_FILE}"
    echo "🗺️  Tile di routing: ${WORK_DIR}/valhalla_tiles/"
    
    if [[ "$TRAFFIC_ENABLED" == "true" ]]; then
        echo "🚦 Dati traffico: ${WORK_DIR}/traffic/"
        echo ""
        echo "💡 Per aggiornare i dati del traffico:"
        echo "   1. Modifica i file CSV in ${WORK_DIR}/traffic/"
        echo "      ⚡ NB: Fare chiarezza su live- e predicted traffic!!!"
        echo "      Puoi utilizzare lo script update_traffic.py in /valhalla_tiles/traffic:"
        echo "      e.g.: cd /valhalla_tiles/traffic; python3 update_traffic.py 173167308 /valhalla_tiles/valhalla_tiles/way_edges.txt"
        echo "      Generate the traffic archive:"
        echo "      valhalla_traffic_demo_utils --config /valhalla_tiles/valhalla.json --generate-live-traffic 1/47701/0,20,`date +%s`"
        echo "   2. Esegui: valhalla_add_predicted_traffic -t traffic --config $CONFIG_FILE"
    fi
    
    echo ""
    echo "🚀 Avvia il servizio con:"
    echo "   valhalla_service ${WORK_DIR}/${CONFIG_FILE}"
}

# Verifica che i comandi necessari siano disponibili
for cmd in valhalla_build_config valhalla_build_tiles wget; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ Errore: Comando '$cmd' non trovato" >&2
        exit 1
    fi
done

# Esegui la funzione principale
main "$@"
# valhalla_traffic_demo_utils --config ${WORK_DIR}/valhalla.json --generate-live-traffic 1/47701/0,20,`date +%s`