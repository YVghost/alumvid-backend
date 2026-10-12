// =========================================================================
// ALUMVID LOGISTICS & FLEET MANAGEMENT PLATFORM - JAVASCRIPT
// =========================================================================

const API_BASE = (window.location.protocol === 'file:' || (window.location.port !== '8080' && window.location.port !== ''))
  ? 'http://localhost:8080'
  : '';
const AUTH_API = `${API_BASE}/api/v1/auth`;
const LOGISTICA_API = `${API_BASE}/api/v1/logistica`;
const WS_ENDPOINT = 'http://localhost:8083/ws-logistica';

// Estado global de la aplicacion
let authToken = localStorage.getItem('alumvid_token') || null;
let currentUser = null;
let allUsuarios = [];
let allChoferes = [];
let allPedidos = [];
let allDespachos = [];
let allRutas = [];
let activeRutaId = null;
let pickerContext = 'agregar'; // 'agregar' o 'editar'

// Google Maps & Telemetria
let googleMap = null;
let activeDriverMarker = null;
let destinationMarkers = [];
let stompClient = null;
let currentTrackingDespachoId = null;

// Selector de Ubicaciones en Google Maps y Planificador Multi-Destino
let pickerMap = null;
let pickerMarker = null;
let pickerGeocoder = null;
let selectedPickerLat = -0.1807;
let selectedPickerLon = -78.4678;
let selectedPickerAddress = 'Av. Amazonas y Orellana, Quito';
let paradasPreparadas = [];

// Simulador Movil
let simActiveDespacho = null;
let simGpsInterval = null;
let simCurrentLat = -0.1807;
let simCurrentLon = -78.4678;
let simPhotoBase64 = null;
let simCanvas = null;
let simCtx = null;
let simIsDrawing = false;
let simHasDrawn = false;

// Inicializacion al cargar el DOM
document.addEventListener('DOMContentLoaded', async () => {
  setupNavigation();
  setupSignatureCanvas();
  setupEventListeners();
  updatePhoneClock();
  setInterval(updatePhoneClock, 30000);

  if (authToken) {
    document.getElementById('logged-user-email').innerText = 'admin@alumvid.com';
    initGoogleMap();
    connectWebSocket();
    await loadAllData();
  } else {
    showLoginModal();
  }
});

// -------------------------------------------------------------------------
// NOTIFICACIONES TOAST (SIN EMOJIS)
// -------------------------------------------------------------------------
function showToast(message, type = 'success') {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  const prefix = type === 'success' ? '[INFO]' : type === 'error' ? '[ERROR]' : '[ALERTA]';
  toast.innerHTML = `<span style="font-family: monospace; font-size: 0.75rem;">${prefix}</span> <span>${message}</span>`;
  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    setTimeout(() => toast.remove(), 300);
  }, 4000);
}

// -------------------------------------------------------------------------
// MODAL DE INICIO DE SESION PARA ADMINISTRADOR (JWT)
// -------------------------------------------------------------------------
function showLoginModal() {
  document.getElementById('modal-login')?.classList.add('active');
}

function hideLoginModal() {
  document.getElementById('modal-login')?.classList.remove('active');
}

function getAuthHeaders() {
  const headers = { 'Content-Type': 'application/json' };
  if (authToken) {
    headers['Authorization'] = `Bearer ${authToken}`;
  }
  return headers;
}

// -------------------------------------------------------------------------
// NAVEGACION POR PESTAÑAS
// -------------------------------------------------------------------------
function setupNavigation() {
  const navItems = document.querySelectorAll('.nav-item');
  const viewTitle = document.getElementById('view-title');
  const viewSubtitle = document.getElementById('view-subtitle');

  navItems.forEach(item => {
    item.addEventListener('click', () => {
      navItems.forEach(n => n.classList.remove('active'));
      item.classList.add('active');

      const targetTab = item.getAttribute('data-tab');
      document.querySelectorAll('.tab-view').forEach(t => t.classList.remove('active'));
      document.getElementById(targetTab).classList.add('active');

      if (targetTab === 'tab-monitoreo') {
        viewTitle.innerText = 'Monitoreo Cartografico en Tiempo Real';
        viewSubtitle.innerText = 'Supervision satelital de rutas de distribucion y telemetria GPS activa';
        if (googleMap) {
          google.maps.event.trigger(googleMap, 'resize');
        }
      } else if (targetTab === 'tab-kanban') {
        viewTitle.innerText = 'Tablero Kanban de Hojas de Ruta';
        viewSubtitle.innerText = 'Supervision del estado de despacho, consentimiento del chofer y cierre e-PoD';
      } else if (targetTab === 'tab-despachos') {
        viewTitle.innerText = 'Planificacion y Asignacion de Rutas';
        viewSubtitle.innerText = 'Georreferenciacion de clientes y asignacion de choferes responsables';
      } else if (targetTab === 'tab-usuarios') {
        viewTitle.innerText = 'Gestion Centralizada de Usuarios (RBAC)';
        viewSubtitle.innerText = 'Creacion de cuentas y asignacion de credenciales para personal y choferes';
        loadUsuarios();
      } else if (targetTab === 'tab-simulator') {
        viewTitle.innerText = 'Simulador de Smartphone del Chofer';
        viewSubtitle.innerText = 'Entorno de pruebas para consentimiento de viaje, telemetria y cierre documentado';
        loadSimulatorDispatches();
      }
    });
  });
}

// -------------------------------------------------------------------------
// GOOGLE MAPS PLATFORM - INTEGRACION CARTOGRAFICA
// -------------------------------------------------------------------------
function initGoogleMap() {
  const mapElement = document.getElementById('google-map-view');
  if (!mapElement || typeof google === 'undefined') return;

  // Centro de Quito
  const quitoCenter = { lat: -0.1807, lng: -78.4678 };

  // Paleta oscura técnica profesional
  const darkMapStyles = [
    { elementType: 'geometry', stylers: [{ color: '#111827' }] },
    { elementType: 'labels.text.stroke', stylers: [{ color: '#111827' }] },
    { elementType: 'labels.text.fill', stylers: [{ color: '#94a3b8' }] },
    { featureType: 'administrative.locality', elementType: 'labels.text.fill', stylers: [{ color: '#cbd5e1' }] },
    { featureType: 'road', elementType: 'geometry', stylers: [{ color: '#1e293b' }] },
    { featureType: 'road', elementType: 'geometry.stroke', stylers: [{ color: '#0f172a' }] },
    { featureType: 'road', elementType: 'labels.text.fill', stylers: [{ color: '#64748b' }] },
    { featureType: 'road.highway', elementType: 'geometry', stylers: [{ color: '#2563eb' }] },
    { featureType: 'transit', elementType: 'geometry', stylers: [{ color: '#1e293b' }] },
    { featureType: 'water', elementType: 'geometry', stylers: [{ color: '#080d1a' }] },
    { featureType: 'water', elementType: 'labels.text.fill', stylers: [{ color: '#3b82f6' }] }
  ];

  googleMap = new google.maps.Map(mapElement, {
    center: quitoCenter,
    zoom: 13,
    styles: darkMapStyles,
    disableDefaultUI: false,
    zoomControl: true,
    mapTypeControl: false,
    streetViewControl: false
  });

  // Marcador del chofer en transito (vectorial con icono SVG moderno)
  activeDriverMarker = new google.maps.Marker({
    position: quitoCenter,
    map: googleMap,
    title: 'Unidad de Transporte en Transito',
    icon: {
      path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
      scale: 6,
      fillColor: '#38bdf8',
      fillOpacity: 1,
      strokeColor: '#0284c7',
      strokeWeight: 2,
      rotation: 0
    }
  });
}

function updateDriverMapPosition(lat, lng, speed, driverName) {
  if (!googleMap || !activeDriverMarker) return;

  const newPos = new google.maps.LatLng(lat, lng);
  activeDriverMarker.setPosition(newPos);

  // Actualizar panel lateral de telemetria
  document.getElementById('tel-latitud').innerText = lat.toFixed(5);
  document.getElementById('tel-longitud').innerText = lng.toFixed(5);
  document.getElementById('tel-velocidad').innerText = `${speed ? speed.toFixed(1) : '24.5'} km/h`;
  document.getElementById('tel-timestamp').innerText = new Date().toLocaleTimeString();
  if (driverName) {
    document.getElementById('tel-chofer-nombre').innerText = driverName;
  }
}

// -------------------------------------------------------------------------
// WEBSOCKET STOMP - TELEMETRIA Y SINCRONIZACION
// -------------------------------------------------------------------------
function connectWebSocket() {
  try {
    const socket = new SockJS(WS_ENDPOINT);
    stompClient = Stomp.over(socket);
    stompClient.debug = null; // Silenciar logs extensos para produccion

    stompClient.connect({}, frame => {
      document.getElementById('ws-status-badge').innerText = 'WebSocket Conectado (STOMP)';
      document.getElementById('ws-status-badge').style.color = '#34d399';

      // 1. Suscripcion a actualizacion general de flota
      stompClient.subscribe('/topic/choferes-activos', message => {
        const payload = JSON.parse(message.body);
        updateDriverMapPosition(payload.latitud, payload.longitud, payload.velocidadKmh, 'Chofer en Ruta');
      });

      // 2. Suscripcion a cambios en el tablero Kanban
      stompClient.subscribe('/topic/tablero-actualizaciones', () => {
        loadAllData();
      });

    }, error => {
      console.warn('Fallo de conexion WebSocket:', error);
      document.getElementById('ws-status-badge').innerText = 'Reconectando WebSocket...';
      document.getElementById('ws-status-badge').style.color = '#fbbf24';
      setTimeout(connectWebSocket, 5000);
    });
  } catch (e) {
    console.error('Error inicializando WebSocket:', e);
  }
}

function subscribeToSpecificDispatch(despachoId) {
  if (!stompClient || !stompClient.connected) return;

  currentTrackingDespachoId = despachoId;
  document.getElementById('tel-despacho-id').innerText = despachoId.substring(0, 8);

  stompClient.subscribe(`/topic/despachos/${despachoId}/ubicacion`, message => {
    const payload = JSON.parse(message.body);
    updateDriverMapPosition(payload.latitud, payload.longitud, payload.velocidadKmh, 'Chofer Asignado');
  });

  stompClient.subscribe(`/topic/despachos/${despachoId}/estado`, message => {
    const payload = JSON.parse(message.body);
    showToast(`Estado de ruta actualizado a: ${payload.estado}`, 'warning');
    loadAllData();
  });
}

// -------------------------------------------------------------------------
// CARGA Y SINCRONIZACION GENERAL DE DATOS
// -------------------------------------------------------------------------
async function loadAllData() {
  try {
    const [pedidosRes, choferesRes, despachosRes, rutasRes] = await Promise.all([
      fetch(`${LOGISTICA_API}/pedidos`).then(r => r.json()).catch(() => []),
      fetch(`${LOGISTICA_API}/choferes`).then(r => r.json()).catch(() => []),
      fetch(`${LOGISTICA_API}/despachos`).then(r => r.json()).catch(() => []),
      fetch(`${LOGISTICA_API}/rutas`).then(r => r.json()).catch(() => [])
    ]);

    allPedidos = pedidosRes || [];
    allChoferes = choferesRes || [];
    allDespachos = despachosRes || [];
    allRutas = rutasRes || [];

    updateStats();
    renderKanban();
    populateSelects();
    renderDestinationMarkersOnMap();
    renderRutasCards();
    if (activeRutaId) {
      renderActiveRuta(activeRutaId);
    }
  } catch (error) {
    console.error('Error cargando datos logisticos:', error);
  }
}

function updateStats() {
  document.getElementById('stat-total-pedidos').innerText = allPedidos.length;
  document.getElementById('stat-en-curso').innerText = allDespachos.filter(d => d.estado === 'EN_CURSO').length;
  document.getElementById('stat-entregados').innerText = allDespachos.filter(d => d.estado === 'ENTREGADO').length;
  document.getElementById('stat-alertas').innerText = allDespachos.filter(d => d.alertaDesviacion === true).length;
}

function renderDestinationMarkersOnMap() {
  if (!googleMap) return;

  // Limpiar marcadores previos de destinos
  destinationMarkers.forEach(m => m.setMap(null));
  destinationMarkers = [];

  allDespachos.filter(d => d.estado === 'EN_CURSO' || d.estado === 'PENDIENTE').forEach(d => {
    const marker = new google.maps.Marker({
      position: { lat: d.pedido.latitudDestino, lng: d.pedido.longitudDestino },
      map: googleMap,
      title: `${d.pedido.cliente} - ${d.pedido.direccionTexto}`,
      icon: {
        path: google.maps.SymbolPath.CIRCLE,
        scale: 7,
        fillColor: '#f59e0b',
        fillOpacity: 0.9,
        strokeColor: '#d97706',
        strokeWeight: 2
      }
    });
    destinationMarkers.push(marker);
  });
}

// -------------------------------------------------------------------------
// FUNCIONES DEL SELECTOR DE GOOGLE MAPS & GESTION DE PARADAS MULTI-DESTINO
// -------------------------------------------------------------------------
function openMapPickerModal(context = 'agregar') {
  pickerContext = context;
  const modal = document.getElementById('modal-map-picker');
  if (!modal) return;
  modal.classList.add('active');

  let currentLat, currentLon, currentAddress;
  if (pickerContext === 'editar') {
    currentLat = parseFloat(document.getElementById('edit-destino-latitud')?.value) || -0.1807;
    currentLon = parseFloat(document.getElementById('edit-destino-longitud')?.value) || -78.4678;
    currentAddress = document.getElementById('edit-destino-direccion')?.value || 'Quito, Ecuador';
  } else {
    currentLat = parseFloat(document.getElementById('destino-latitud')?.value) || -0.1807;
    currentLon = parseFloat(document.getElementById('destino-longitud')?.value) || -78.4678;
    currentAddress = document.getElementById('destino-direccion')?.value || 'Quito, Ecuador';
  }

  selectedPickerLat = currentLat;
  selectedPickerLon = currentLon;
  selectedPickerAddress = currentAddress;

  const addrEl = document.getElementById('map-picker-current-address');
  const coordEl = document.getElementById('map-picker-current-coords');
  if (addrEl) addrEl.innerText = selectedPickerAddress;
  if (coordEl) coordEl.innerText = `${selectedPickerLat.toFixed(5)}, ${selectedPickerLon.toFixed(5)}`;

  setTimeout(() => {
    if (!pickerMap) {
      const canvas = document.getElementById('map-picker-canvas');
      if (!canvas || typeof google === 'undefined' || !google.maps) return;

      pickerGeocoder = new google.maps.Geocoder();
      pickerMap = new google.maps.Map(canvas, {
        center: { lat: selectedPickerLat, lng: selectedPickerLon },
        zoom: 14,
        mapTypeId: google.maps.MapTypeId.ROADMAP,
        styles: [
          { elementType: 'geometry', stylers: [{ color: '#1e293b' }] },
          { elementType: 'labels.text.stroke', stylers: [{ color: '#0f172a' }] },
          { elementType: 'labels.text.fill', stylers: [{ color: '#94a3b8' }] },
          { featureType: 'road', elementType: 'geometry', stylers: [{ color: '#334155' }] },
          { featureType: 'road', elementType: 'geometry.stroke', stylers: [{ color: '#1e293b' }] },
          { featureType: 'road', elementType: 'labels.text.fill', stylers: [{ color: '#cbd5e1' }] },
          { featureType: 'water', elementType: 'geometry', stylers: [{ color: '#0f172a' }] }
        ]
      });

      pickerMarker = new google.maps.Marker({
        position: { lat: selectedPickerLat, lng: selectedPickerLon },
        map: pickerMap,
        draggable: true,
        animation: google.maps.Animation.DROP,
        title: 'Punto de entrega'
      });

      pickerMap.addListener('click', e => {
        setPickerLocation(e.latLng);
      });

      pickerMarker.addListener('dragend', e => {
        setPickerLocation(e.latLng);
      });
    } else {
      google.maps.event.trigger(pickerMap, 'resize');
      pickerMap.setCenter({ lat: selectedPickerLat, lng: selectedPickerLon });
      if (pickerMarker) {
        pickerMarker.setPosition({ lat: selectedPickerLat, lng: selectedPickerLon });
      }
    }
  }, 200);
}

function setPickerLocation(latLng) {
  selectedPickerLat = latLng.lat();
  selectedPickerLon = latLng.lng();
  if (pickerMarker) pickerMarker.setPosition(latLng);

  const coordEl = document.getElementById('map-picker-current-coords');
  const addrEl = document.getElementById('map-picker-current-address');
  if (coordEl) coordEl.innerText = `${selectedPickerLat.toFixed(5)}, ${selectedPickerLon.toFixed(5)}`;
  if (addrEl) addrEl.innerText = 'Consultando dirección satelital...';

  if (pickerGeocoder) {
    pickerGeocoder.geocode({ location: latLng }, (results, status) => {
      if (status === 'OK' && results && results[0]) {
        selectedPickerAddress = results[0].formatted_address;
      } else {
        selectedPickerAddress = `Coordenadas: ${selectedPickerLat.toFixed(4)}, ${selectedPickerLon.toFixed(4)}`;
      }
      if (addrEl) addrEl.innerText = selectedPickerAddress;
    });
  }
}

function searchMapPickerLocation() {
  const query = document.getElementById('map-picker-search-input')?.value.trim();
  if (!query) return;

  if (pickerGeocoder) {
    const fullQuery = query.toLowerCase().includes('quito') ? query : `${query}, Quito, Ecuador`;
    pickerGeocoder.geocode({ address: fullQuery }, (results, status) => {
      if (status === 'OK' && results && results[0]) {
        const loc = results[0].geometry.location;
        if (pickerMap) {
          pickerMap.setCenter(loc);
          pickerMap.setZoom(16);
        }
        setPickerLocation(loc);
      } else {
        showToast('No se encontró el sitio indicado en Quito. Puede seleccionarlo con un clic directo en el mapa.', 'warning');
      }
    });
  }
}

function closeMapPickerModal() {
  document.getElementById('modal-map-picker')?.classList.remove('active');
}

function confirmMapPickerSelection() {
  if (pickerContext === 'editar') {
    const inputDir = document.getElementById('edit-destino-direccion');
    const inputLat = document.getElementById('edit-destino-latitud');
    const inputLon = document.getElementById('edit-destino-longitud');
    const badge = document.getElementById('edit-coords-badge');

    if (inputDir) inputDir.value = selectedPickerAddress;
    if (inputLat) inputLat.value = selectedPickerLat.toFixed(6);
    if (inputLon) inputLon.value = selectedPickerLon.toFixed(6);
    if (badge) badge.innerText = `Ubicación: ${selectedPickerLat.toFixed(4)}, ${selectedPickerLon.toFixed(4)}`;
  } else {
    const inputDir = document.getElementById('destino-direccion');
    const inputLat = document.getElementById('destino-latitud');
    const inputLon = document.getElementById('destino-longitud');
    const badge = document.getElementById('destino-coordenadas-badge');

    if (inputDir) inputDir.value = selectedPickerAddress;
    if (inputLat) inputLat.value = selectedPickerLat.toFixed(6);
    if (inputLon) inputLon.value = selectedPickerLon.toFixed(6);
    if (badge) {
      const shortAddr = selectedPickerAddress.length > 35 ? selectedPickerAddress.substring(0, 32) + '...' : selectedPickerAddress;
      badge.innerText = `Ubicacion: ${selectedPickerLat.toFixed(4)}, ${selectedPickerLon.toFixed(4)} (${shortAddr})`;
    }
  }

  closeMapPickerModal();
  showToast('Ubicación fijada desde Google Maps.', 'success');
}

// -------------------------------------------------------------------------
// GESTION INTEGRAL DE RUTAS Y N DESTINOS DINAMICOS
// -------------------------------------------------------------------------
function renderRutasCards() {
  const container = document.getElementById('rutas-cards-container');
  const countBadge = document.getElementById('rutas-count-badge');
  if (countBadge) countBadge.innerText = allRutas.length;
  if (!container) return;

  if (allRutas.length === 0) {
    container.innerHTML = `
      <div style="text-align: center; color: var(--text-dim); padding: 1.5rem; font-size: 0.82rem;">
        No hay rutas creadas. Cree una nueva ruta arriba.
      </div>
    `;
    return;
  }

  container.innerHTML = allRutas.map(r => {
    const isActive = r.id === activeRutaId;
    const numParadas = r.paradas ? r.paradas.length : 0;
    const tagClass = r.estado === 'EN_CURSO' ? 'tag-en-curso' : r.estado === 'FINALIZADA' ? 'tag-delivered' : 'tag-pending';
    const borderStyle = isActive
      ? 'border: 2px solid #3b82f6; background: rgba(59, 130, 246, 0.12);'
      : 'border: 1px solid var(--border-subtle); background: var(--bg-card);';

    return `
      <div style="${borderStyle} border-radius: 8px; padding: 12px; cursor: pointer; transition: all 0.2s;"
           onclick="seleccionarRuta('${r.id}')">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
          <strong style="font-size: 0.95rem; color: white;">${r.codigoRuta}</strong>
          <span class="tag-status ${tagClass}" style="font-size: 0.68rem;">${r.estado}</span>
        </div>
        <div style="font-size: 0.78rem; color: var(--text-muted); margin-bottom: 4px;">
          Chofer: <span style="color: ${r.choferNombre ? '#cbd5e1' : '#fbbf24'}; font-weight: 600;">
            ${r.choferNombre || 'Sin asignar'}
          </span>
        </div>
        <div style="display: flex; justify-content: space-between; align-items: center; font-size: 0.72rem; color: var(--text-dim);">
          <span>Destinos: <strong style="color: #60a5fa;">${numParadas}</strong></span>
          <span>${r.fechaCreacion ? new Date(r.fechaCreacion).toLocaleDateString() : ''}</span>
        </div>
      </div>
    `;
  }).join('');
}

function seleccionarRuta(rutaId) {
  activeRutaId = rutaId;
  renderRutasCards();
  renderActiveRuta(rutaId);
}

function renderActiveRuta(rutaId) {
  const panelVacio = document.getElementById('panel-ruta-seleccionada-vacio');
  const panelActivo = document.getElementById('panel-ruta-activa');
  if (!panelVacio || !panelActivo) return;

  const ruta = allRutas.find(r => r.id === rutaId);
  if (!ruta) {
    activeRutaId = null;
    panelVacio.style.display = 'block';
    panelActivo.style.display = 'none';
    return;
  }

  panelVacio.style.display = 'none';
  panelActivo.style.display = 'flex';

  // Cabecera de la ruta
  document.getElementById('activa-codigo-ruta').innerText = ruta.codigoRuta;
  const tagEstado = document.getElementById('activa-estado-tag');
  tagEstado.innerText = ruta.estado;
  tagEstado.className = `tag-status ${ruta.estado === 'EN_CURSO' ? 'tag-en-curso' : ruta.estado === 'FINALIZADA' ? 'tag-delivered' : 'tag-pending'}`;

  const infoChofer = document.getElementById('activa-info-chofer');
  infoChofer.innerHTML = `Chofer asignado: <strong>${ruta.choferNombre ? `${ruta.choferNombre} (${ruta.choferTelefono || 'Sin tel'})` : '<span style="color: #fbbf24;">Sin asignar</span>'}</strong>`;

  const selectReasignar = document.getElementById('select-reasignar-chofer');
  if (selectReasignar) {
    selectReasignar.value = ruta.choferId || '';
  }

  // Destinos / Paradas
  const paradas = ruta.paradas || [];
  document.getElementById('activa-count-paradas').innerText = paradas.length;

  const tbody = document.getElementById('activa-destinos-table-body');
  if (paradas.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="5" style="text-align: center; color: var(--text-dim); padding: 1.5rem;">
          No hay destinos agregados a esta ruta. Utilice el formulario superior para añadir paradas.
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = paradas.map((p, idx) => {
    const orden = p.ordenParada != null ? p.ordenParada : idx + 1;
    const tagClass = p.estado === 'EN_CURSO' ? 'tag-en-curso' : p.estado === 'ENTREGADO' ? 'tag-delivered' : p.estado === 'CANCELADA' ? 'tag-canceled' : 'tag-pending';
    const lat = p.pedido ? p.pedido.latitudDestino : 0;
    const lon = p.pedido ? p.pedido.longitudDestino : 0;
    const cliente = p.pedido ? p.pedido.cliente : 'Cliente';
    const direccion = p.pedido ? p.pedido.direccionTexto : '';

    return `
      <tr>
        <td style="font-weight: 700; color: #60a5fa; text-align: center;">#${orden}</td>
        <td style="font-weight: 700; color: white;">${cliente}</td>
        <td>
          <div style="color: var(--text-muted); font-size: 0.8rem;">${direccion}</div>
          <div style="font-family: monospace; font-size: 0.72rem; color: #34d399;">${Number(lat).toFixed(4)}, ${Number(lon).toFixed(4)}</div>
        </td>
        <td><span class="tag-status ${tagClass}" style="font-size: 0.68rem;">${p.estado}</span></td>
        <td style="text-align: center;">
          <button type="button" class="btn btn-outline" style="padding: 2px 8px; font-size: 0.72rem; margin-right: 4px;"
                  onclick="abrirModalEditarDestino('${p.id}')">
            Editar
          </button>
          <button type="button" class="btn btn-danger" style="padding: 2px 8px; font-size: 0.72rem;"
                  onclick="eliminarDestinoDeRuta('${p.id}')">
            Eliminar
          </button>
        </td>
      </tr>
    `;
  }).join('');
}

function abrirModalEditarDestino(despachoId) {
  const ruta = allRutas.find(r => r.id === activeRutaId);
  if (!ruta || !ruta.paradas) return;

  const p = ruta.paradas.find(x => x.id === despachoId);
  if (!p) return;

  document.getElementById('edit-despacho-id').value = p.id;
  document.getElementById('edit-destino-cliente').value = p.pedido.cliente;
  document.getElementById('edit-destino-direccion').value = p.pedido.direccionTexto;
  document.getElementById('edit-destino-latitud').value = p.pedido.latitudDestino;
  document.getElementById('edit-destino-longitud').value = p.pedido.longitudDestino;
  document.getElementById('edit-destino-comentarios').value = p.comentarios || '';

  const badge = document.getElementById('edit-coords-badge');
  if (badge) {
    badge.innerText = `Ubicación: ${Number(p.pedido.latitudDestino).toFixed(4)}, ${Number(p.pedido.longitudDestino).toFixed(4)}`;
  }

  document.getElementById('modal-editar-destino')?.classList.add('active');
}

function cerrarModalEditarDestino() {
  document.getElementById('modal-editar-destino')?.classList.remove('active');
}

async function eliminarDestinoDeRuta(despachoId) {
  if (!confirm('¿Confirma que desea eliminar este destino de la hoja de ruta?')) return;
  try {
    const res = await fetch(`${LOGISTICA_API}/rutas/${activeRutaId}/destinos/${despachoId}`, {
      method: 'DELETE',
      headers: getAuthHeaders()
    });
    if (!res.ok) throw new Error('Error al eliminar destino.');
    showToast('Destino eliminado de la ruta.', 'success');
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

function populateSelects() {
  // Choferes para crear ruta
  const selectChoferCrear = document.getElementById('select-chofer-crear-ruta');
  if (selectChoferCrear) {
    const prevVal = selectChoferCrear.value;
    selectChoferCrear.innerHTML = '<option value="">-- Sin asignar (asignar despues) --</option>' + allChoferes.map(c => `
      <option value="${c.id}">${c.nombre} (${c.estadoDisponibilidad})</option>
    `).join('');
    if (prevVal) selectChoferCrear.value = prevVal;
  }

  // Choferes para reasignar en ruta activa
  const selectReasignar = document.getElementById('select-reasignar-chofer');
  if (selectReasignar) {
    const prevVal = selectReasignar.value;
    selectReasignar.innerHTML = '<option value="">-- Sin chofer asignado --</option>' + allChoferes.map(c => `
      <option value="${c.id}">${c.nombre} (${c.estadoDisponibilidad})</option>
    `).join('');
    if (prevVal) selectReasignar.value = prevVal;
  }

  // Choferes en simulador
  const simSelect = document.getElementById('sim-select-chofer');
  if (simSelect) {
    const prevVal = simSelect.value;
    simSelect.innerHTML = allChoferes.map(c => `
      <option value="${c.id}">${c.nombre}</option>
    `).join('');
    if (prevVal) simSelect.value = prevVal;
  }
}

// -------------------------------------------------------------------------
// TABLERO KANBAN (4 COLUMNAS FORMALES)
// -------------------------------------------------------------------------
function renderKanban() {
  const colPendientes = document.getElementById('kanban-list-pendientes');
  const colEnCurso = document.getElementById('kanban-list-encurso');
  const colEntregados = document.getElementById('kanban-list-entregados');
  const colCanceladas = document.getElementById('kanban-list-canceladas');

  const pendientes = allDespachos.filter(d => d.estado === 'PENDIENTE');
  const enCurso = allDespachos.filter(d => d.estado === 'EN_CURSO');
  const entregados = allDespachos.filter(d => d.estado === 'ENTREGADO');
  const canceladas = allDespachos.filter(d => d.estado === 'CANCELADA');

  document.getElementById('count-col-pendientes').innerText = pendientes.length;
  document.getElementById('count-col-encurso').innerText = enCurso.length;
  document.getElementById('count-col-entregados').innerText = entregados.length;
  document.getElementById('count-col-canceladas').innerText = canceladas.length;

  colPendientes.innerHTML = pendientes.length === 0
    ? '<p style="font-size: 0.78rem; color: var(--text-dim); text-align: center; margin-top: 2rem;">Sin rutas pendientes de aprobacion</p>'
    : pendientes.map(d => renderCardHtml(d, 'PENDIENTE')).join('');

  colEnCurso.innerHTML = enCurso.length === 0
    ? '<p style="font-size: 0.78rem; color: var(--text-dim); text-align: center; margin-top: 2rem;">Sin unidades en transito activo</p>'
    : enCurso.map(d => renderCardHtml(d, 'EN_CURSO')).join('');

  colEntregados.innerHTML = entregados.length === 0
    ? '<p style="font-size: 0.78rem; color: var(--text-dim); text-align: center; margin-top: 2rem;">Sin entregas documentadas hoy</p>'
    : entregados.map(d => renderCardHtml(d, 'ENTREGADO')).join('');

  colCanceladas.innerHTML = canceladas.length === 0
    ? '<p style="font-size: 0.78rem; color: var(--text-dim); text-align: center; margin-top: 2rem;">Sin rutas canceladas</p>'
    : canceladas.map(d => renderCardHtml(d, 'CANCELADA')).join('');
}

function renderCardHtml(d, status) {
  const shortId = d.id ? d.id.substring(0, 8) : '--------';
  const clienteNombre = d.pedido ? d.pedido.cliente : 'Cliente';
  const direccionDestino = d.pedido ? d.pedido.direccionTexto : 'Destino no especificado';
  const choferNombre = d.chofer ? d.chofer.nombre : 'Sin asignar';

  let statusBadge = '';
  let actions = '';

  if (status === 'PENDIENTE') {
    statusBadge = '<span class="tag-status tag-pending">Pendiente Consentimiento</span>';
    actions = d.chofer
      ? `
        <button class="btn btn-outline" style="width: 100%; font-size: 0.75rem; padding: 6px;" onclick="openInSimulator('${d.chofer.id}', '${d.id}')">
          Ver en App del Chofer
        </button>
      `
      : `<div style="font-size: 0.72rem; color: #fbbf24; text-align: center; padding: 4px;">Chofer pendiente de asignacion</div>`;
  } else if (status === 'EN_CURSO') {
    statusBadge = '<span class="tag-status tag-en-curso">En Transito [GPS ON]</span>';
    const lat = d.pedido ? d.pedido.latitudDestino : -0.18;
    const lng = d.pedido ? d.pedido.longitudDestino : -78.46;
    actions = `
      <button class="btn btn-primary" style="width: 100%; font-size: 0.75rem; padding: 6px;" onclick="trackRouteOnMap('${d.id}', ${lat}, ${lng})">
        Rastrear en Google Maps
      </button>
    `;
  } else if (status === 'ENTREGADO') {
    statusBadge = d.alertaDesviacion
      ? `<span class="tag-status tag-canceled">Alerta Desvio: ${Math.round(d.desviacionMetros || 0)}m</span>`
      : `<span class="tag-status tag-delivered">Verificado (${Math.round(d.desviacionMetros || 0)}m)</span>`;
    actions = `
      <button class="btn btn-outline" style="width: 100%; font-size: 0.75rem; padding: 6px;" onclick="viewEvidenceModal('${d.id}')">
        Auditoria e-PoD
      </button>
    `;
  } else if (status === 'CANCELADA') {
    statusBadge = '<span class="tag-status tag-canceled">Cancelada por Chofer</span>';
    actions = `<div style="font-size: 0.72rem; color: var(--text-dim);">${d.comentarios || 'Cancelada'}</div>`;
  }

  return `
    <div class="kanban-card">
      <div class="card-header-row">
        <span class="card-order-id">#${shortId}</span>
        ${statusBadge}
      </div>
      <div class="card-client-name">${clienteNombre}</div>
      <div class="card-address">Destino: ${direccionDestino}</div>
      <div style="font-size: 0.75rem; color: var(--text-muted);">
        Chofer: <strong style="color: var(--text-main);">${choferNombre}</strong>
      </div>
      <div style="margin-top: 4px;">
        ${actions}
      </div>
    </div>
  `;
}

function trackRouteOnMap(despachoId, destLat, destLng) {
  document.querySelector('.nav-item[data-tab="tab-monitoreo"]').click();
  subscribeToSpecificDispatch(despachoId);
  if (googleMap) {
    googleMap.setCenter({ lat: destLat, lng: destLng });
    googleMap.setZoom(15);
  }
}

// -------------------------------------------------------------------------
// GESTION CENTRALIZADA DE USUARIOS (AUTH SERVICE & RBAC)
// -------------------------------------------------------------------------
async function loadUsuarios() {
  try {
    const res = await fetch(`${AUTH_API}/usuarios`, {
      headers: getAuthHeaders()
    });
    if (!res.ok) throw new Error('No autorizado');

    allUsuarios = await res.json();
    const tbody = document.getElementById('usuarios-table-body');

    if (allUsuarios.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align: center;">No hay usuarios registrados</td></tr>';
      return;
    }

    tbody.innerHTML = allUsuarios.map(u => {
      const isMasterAdmin = u.email === 'admin@alumvid.com';
      const actionsHtml = isMasterAdmin
        ? '<span style="font-size: 0.72rem; color: var(--text-dim); font-style: italic;">Cuenta Protegida</span>'
        : `
          <div style="display: flex; gap: 6px; justify-content: center;">
            <button class="btn btn-outline" style="padding: 3px 8px; font-size: 0.72rem;" onclick="toggleUserStatus('${u.id}', ${!u.activo})">
              ${u.activo ? 'Suspender' : 'Activar'}
            </button>
            <button class="btn btn-danger" style="padding: 3px 8px; font-size: 0.72rem;" onclick="eliminarUsuarioClick('${u.id}', '${u.email}', '${u.rol}')">
              Eliminar
            </button>
          </div>
        `;

      return `
        <tr>
          <td style="font-weight: 700;">${u.nombre}</td>
          <td style="font-family: monospace;">${u.email}</td>
          <td>${u.telefono || '-'}</td>
          <td><span class="tag-status ${u.rol === 'ROLE_ADMIN' ? 'tag-en-curso' : 'tag-pending'}">${u.rol}</span></td>
          <td>
            <span style="font-size: 0.75rem; color: ${u.activo ? '#34d399' : '#fb7185'}; font-weight: 700;">
              ${u.activo ? 'ACTIVO' : 'SUSPENDIDO'}
            </span>
          </td>
          <td style="text-align: center;">
            ${actionsHtml}
          </td>
        </tr>
      `;
    }).join('');
  } catch (err) {
    console.error('Error cargando usuarios:', err);
  }
}

async function toggleUserStatus(id, newStatus) {
  try {
    const res = await fetch(`${AUTH_API}/usuarios/${id}/estado`, {
      method: 'PATCH',
      headers: getAuthHeaders(),
      body: JSON.stringify({ activo: newStatus })
    });
    if (!res.ok) throw new Error('Error al actualizar estado del usuario');
    showToast('Estado de usuario modificado exitosamente.', 'success');
    loadUsuarios();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

async function eliminarUsuarioClick(id, email, rol) {
  if (!confirm(`¿Está seguro de eliminar definitivamente al usuario "${email}" del sistema? Esta acción no se puede deshacer.`)) {
    return;
  }

  try {
    const res = await fetch(`${AUTH_API}/usuarios/${id}`, {
      method: 'DELETE',
      headers: getAuthHeaders()
    });

    if (!res.ok) {
      const errorData = await res.json().catch(() => ({}));
      throw new Error(errorData.error || errorData.message || 'Error al eliminar usuario.');
    }

    // Si es un chofer, eliminar tambien de logistica para mantener la sincronizacion
    if (rol === 'ROLE_CHOFER') {
      await fetch(`${LOGISTICA_API}/choferes/${id}`, {
        method: 'DELETE',
        headers: getAuthHeaders()
      }).catch(e => console.warn('Aviso: no se pudo sincronizar eliminacion en logistica:', e));
    }

    showToast(`Usuario "${email}" eliminado permanentemente.`, 'success');
    await loadUsuarios();
    await loadAllData();
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// -------------------------------------------------------------------------
// SIMULADOR DE APP MOVIL DEL CHOFER
// -------------------------------------------------------------------------
function updatePhoneClock() {
  const now = new Date();
  const el = document.getElementById('phone-clock');
  if (el) el.innerText = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
}

function openInSimulator(choferId, despachoId) {
  document.querySelector('.nav-item[data-tab="tab-simulator"]').click();
  const simSelect = document.getElementById('sim-select-chofer');
  simSelect.value = choferId;
  loadSimulatorDispatches(despachoId);
}

async function loadSimulatorDispatches(autoOpenDespachoId = null) {
  const choferId = document.getElementById('sim-select-chofer').value;
  const container = document.getElementById('phone-dispatches-list');

  if (!choferId) {
    container.innerHTML = '<p style="font-size: 0.8rem; color: var(--text-dim); text-align: center;">Seleccione un chofer para sincronizar.</p>';
    return;
  }

  try {
    const res = await fetch(`${LOGISTICA_API}/choferes/${choferId}/despachos-hoy`);
    const despachos = await res.json();

    if (despachos.length === 0) {
      container.innerHTML = '<p style="font-size: 0.8rem; color: var(--text-dim); text-align: center; padding: 2rem 0;">No posee rutas asignadas hoy.</p>';
      return;
    }

    container.innerHTML = despachos.map(d => `
      <div style="background: #1e293b; border: 1px solid rgba(255,255,255,0.06); border-radius: 6px; padding: 10px; cursor: pointer;"
           onclick="openSimulatorRoute('${d.id}')">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
          <span style="font-size: 0.68rem; color: #60a5fa; font-weight: 700;">#${d.id.substring(0, 6)}</span>
          <span class="tag-status ${d.estado === 'EN_CURSO' ? 'tag-en-curso' : d.estado === 'ENTREGADO' ? 'tag-delivered' : d.estado === 'CANCELADA' ? 'tag-canceled' : 'tag-pending'}" style="font-size: 0.65rem;">
            ${d.estado}
          </span>
        </div>
        <div style="font-size: 0.82rem; font-weight: 700; color: white;">${d.pedido.cliente}</div>
        <div style="font-size: 0.72rem; color: var(--text-muted);">Destino: ${d.pedido.direccionTexto}</div>
      </div>
    `).join('');

    if (autoOpenDespachoId) {
      openSimulatorRoute(autoOpenDespachoId);
    }
  } catch (err) {
    console.error('Error cargando rutas en simulador:', err);
  }
}

function openSimulatorRoute(despachoId) {
  const d = allDespachos.find(x => x.id === despachoId);
  if (!d) return;

  simActiveDespacho = d;
  document.getElementById('sim-route-order-id').innerText = `DESPACHO #${d.id.substring(0, 8)}`;
  document.getElementById('sim-route-client').innerText = d.pedido.cliente;
  document.getElementById('sim-route-address').innerText = `Destino: ${d.pedido.direccionTexto}`;

  const statusTag = document.getElementById('sim-route-status-tag');
  statusTag.innerText = d.estado;

  // Secciones del simulador segun estado
  const consentSec = document.getElementById('sim-section-consent');
  const progressSec = document.getElementById('sim-section-in-progress');
  const podFormSec = document.getElementById('sim-section-pod-form');

  consentSec.style.display = 'none';
  progressSec.style.display = 'none';
  podFormSec.style.display = 'none';

  if (d.estado === 'PENDIENTE') {
    consentSec.style.display = 'flex';
  } else if (d.estado === 'EN_CURSO') {
    progressSec.style.display = 'flex';
    startSimulatedGpsStream(d);
  }

  document.getElementById('phone-view-list').style.display = 'none';
  document.getElementById('phone-view-route').style.display = 'flex';
}

function startSimulatedGpsStream(despacho) {
  stopSimulatedGpsStream();

  // Origen simulado en Quito
  simCurrentLat = -0.1807;
  simCurrentLon = -78.4678;

  simGpsInterval = setInterval(() => {
    // Desplazamiento progresivo hacia el destino
    const destLat = despacho.pedido.latitudDestino;
    const destLon = despacho.pedido.longitudDestino;

    simCurrentLat += (destLat - simCurrentLat) * 0.15;
    simCurrentLon += (destLon - simCurrentLon) * 0.15;

    // Enviar telemetria via WebSocket STOMP al backend
    if (stompClient && stompClient.connected) {
      stompClient.send('/app/telemetria/enviar', {}, JSON.stringify({
        despachoId: despacho.id,
        choferId: despacho.chofer.id,
        latitud: simCurrentLat,
        longitud: simCurrentLon,
        velocidadKmh: 35.0,
        timestamp: Date.now()
      }));
    }
  }, 2500);
}

function stopSimulatedGpsStream() {
  if (simGpsInterval) {
    clearInterval(simGpsInterval);
    simGpsInterval = null;
  }
}

// -------------------------------------------------------------------------
// LIENZO DE FIRMA TACTIL DIGITAL (SIN DEPENDENCIAS)
// -------------------------------------------------------------------------
function setupSignatureCanvas() {
  simCanvas = document.getElementById('sim-signature-canvas');
  if (!simCanvas) return;
  simCtx = simCanvas.getContext('2d');

  simCtx.strokeStyle = '#60a5fa';
  simCtx.lineWidth = 2.5;
  simCtx.lineCap = 'round';

  const startDraw = (x, y) => {
    simIsDrawing = true;
    simHasDrawn = true;
    simCtx.beginPath();
    simCtx.moveTo(x, y);
  };

  const drawMove = (x, y) => {
    if (!simIsDrawing) return;
    simCtx.lineTo(x, y);
    simCtx.stroke();
  };

  const endDraw = () => {
    if (simIsDrawing) {
      simCtx.closePath();
      simIsDrawing = false;
    }
  };

  // Eventos raton
  simCanvas.addEventListener('mousedown', e => startDraw(e.offsetX, e.offsetY));
  simCanvas.addEventListener('mousemove', e => drawMove(e.offsetX, e.offsetY));
  simCanvas.addEventListener('mouseup', endDraw);
  simCanvas.addEventListener('mouseleave', endDraw);

  // Eventos tactiles para smartphone o touchscreen
  simCanvas.addEventListener('touchstart', e => {
    e.preventDefault();
    const rect = simCanvas.getBoundingClientRect();
    startDraw(e.touches[0].clientX - rect.left, e.touches[0].clientY - rect.top);
  });
  simCanvas.addEventListener('touchmove', e => {
    e.preventDefault();
    const rect = simCanvas.getBoundingClientRect();
    drawMove(e.touches[0].clientX - rect.left, e.touches[0].clientY - rect.top);
  });
  simCanvas.addEventListener('touchend', e => {
    e.preventDefault();
    endDraw();
  });

  document.getElementById('sim-btn-clear-signature')?.addEventListener('click', () => {
    simCtx.clearRect(0, 0, simCanvas.width, simCanvas.height);
    simHasDrawn = false;
  });
}

// -------------------------------------------------------------------------
// GESTION DE EVENTOS Y FORMULARIOS
// -------------------------------------------------------------------------
function setupEventListeners() {
  // Boton Cerrar Sesion
  document.getElementById('btn-logout')?.addEventListener('click', () => {
    localStorage.removeItem('alumvid_token');
    authToken = null;
    currentUser = null;
    document.getElementById('logged-user-email').innerText = 'Sin sesion';
    showLoginModal();
    showToast('Sesion cerrada correctamente.', 'info');
  });

  // Alternar visibilidad de contraseña en modal de login
  document.getElementById('btn-toggle-login-password')?.addEventListener('click', () => {
    const pwdInput = document.getElementById('login-admin-password');
    const eyeIcon = document.getElementById('icon-eye-login-password');
    if (!pwdInput) return;
    if (pwdInput.type === 'password') {
      pwdInput.type = 'text';
      eyeIcon.innerHTML = '<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path><line x1="1" y1="1" x2="23" y2="23"></line>';
    } else {
      pwdInput.type = 'password';
      eyeIcon.innerHTML = '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle>';
    }
  });

  // Alternar visibilidad de contraseña en creacion de usuarios
  document.getElementById('btn-toggle-usr-password')?.addEventListener('click', () => {
    const pwdInput = document.getElementById('input-usr-password');
    const eyeIcon = document.getElementById('icon-eye-usr-password');
    if (!pwdInput) return;
    if (pwdInput.type === 'password') {
      pwdInput.type = 'text';
      eyeIcon.innerHTML = '<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path><line x1="1" y1="1" x2="23" y2="23"></line>';
    } else {
      pwdInput.type = 'password';
      eyeIcon.innerHTML = '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle>';
    }
  });

  // Formulario Iniciar Sesion Modal
  document.getElementById('form-login-admin')?.addEventListener('submit', async e => {
    e.preventDefault();
    const email = document.getElementById('login-admin-email').value.trim();
    const password = document.getElementById('login-admin-password').value;
    const errEl = document.getElementById('login-error-msg');
    if (errEl) errEl.style.display = 'none';

    try {
      const res = await fetch(`${AUTH_API}/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, identification: email, password })
      });

      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.message || errData.error || 'Credenciales invalidas');
      }

      const data = await res.json();
      if (data.rol !== 'ROLE_ADMIN') {
        throw new Error('Acceso restringido: requiere permisos de Administrador.');
      }

      authToken = data.token;
      localStorage.setItem('alumvid_token', authToken);
      currentUser = data;
      document.getElementById('logged-user-email').innerText = data.email;
      hideLoginModal();
      showToast('Sesion iniciada exitosamente.', 'success');

      initGoogleMap();
      connectWebSocket();
      await loadAllData();
    } catch (err) {
      if (errEl) {
        if (err.message === 'Failed to fetch' || err.name === 'TypeError') {
          errEl.innerText = 'Error de conexion: no se pudo conectar al API Gateway (http://localhost:8080). Asegurese de que los servicios esten activos.';
        } else {
          errEl.innerText = err.message;
        }
        errEl.style.display = 'block';
      }
    }
  });

  // Boton actualizar global
  document.getElementById('btn-refresh-global')?.addEventListener('click', () => {
    loadAllData();
    showToast('Datos sincronizados con PostGIS y microservicios.', 'success');
  });

  // Boton recentrar mapa
  document.getElementById('btn-recenter-map')?.addEventListener('click', () => {
    if (googleMap && activeDriverMarker) {
      googleMap.panTo(activeDriverMarker.getPosition());
      googleMap.setZoom(15);
    }
  });

  // Selector de preset de ubicacion en Quito
  document.getElementById('select-preset-quito')?.addEventListener('change', e => {
    if (e.target.value !== 'custom') {
      const [lat, lon] = e.target.value.split(',');
      document.getElementById('input-pedido-latitud').value = lat;
      document.getElementById('input-pedido-longitud').value = lon;
    }
  });

  // -------------------------------------------------------------------------
  // SELECTOR INTERACTIVO DE UBICACION EN GOOGLE MAPS
  // -------------------------------------------------------------------------
  document.getElementById('btn-open-map-picker')?.addEventListener('click', () => {
    openMapPickerModal('agregar');
  });
  document.getElementById('btn-close-map-picker')?.addEventListener('click', closeMapPickerModal);
  document.getElementById('btn-cancel-map-picker')?.addEventListener('click', closeMapPickerModal);
  document.getElementById('btn-confirm-map-picker')?.addEventListener('click', confirmMapPickerSelection);
  document.getElementById('btn-map-picker-search')?.addEventListener('click', searchMapPickerLocation);
  document.getElementById('map-picker-search-input')?.addEventListener('keypress', e => {
    if (e.key === 'Enter') {
      e.preventDefault();
      searchMapPickerLocation();
    }
  });

  // Boton refrescar rutas
  document.getElementById('btn-refresh-rutas')?.addEventListener('click', async () => {
    await loadAllData();
    showToast('Directorio de hojas de ruta actualizado.', 'info');
  });

  // -------------------------------------------------------------------------
  // PASO 1: CREAR HOJA DE RUTA
  // -------------------------------------------------------------------------
  document.getElementById('form-crear-ruta-simple')?.addEventListener('submit', async e => {
    e.preventDefault();
    const codigoRuta = document.getElementById('input-codigo-ruta').value.trim();
    const choferId = document.getElementById('select-chofer-crear-ruta').value || null;
    const comentarios = document.getElementById('input-ruta-observaciones').value.trim() || null;

    try {
      const res = await fetch(`${LOGISTICA_API}/rutas/simple`, {
        method: 'POST',
        headers: getAuthHeaders(),
        body: JSON.stringify({ codigoRuta, choferId, comentarios })
      });

      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || errData.message || 'Error al crear la hoja de ruta.');
      }

      const ruta = await res.json();
      activeRutaId = ruta.id;
      showToast(`Hoja de ruta "${ruta.codigoRuta}" creada exitosamente. Proceda a agregar los destinos.`, 'success');

      // Proponer siguiente numero incremental
      const nextMatch = codigoRuta.match(/\d+/);
      const nextNum = nextMatch ? parseInt(nextMatch[0]) + 1 : 2;
      document.getElementById('input-codigo-ruta').value = `Ruta ${nextNum}`;
      document.getElementById('input-ruta-observaciones').value = '';

      await loadAllData();
      seleccionarRuta(ruta.id);
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // -------------------------------------------------------------------------
  // PASO 3: ASIGNAR / REASIGNAR CHOFER A LA RUTA
  // -------------------------------------------------------------------------
  document.getElementById('btn-confirmar-asignacion-chofer')?.addEventListener('click', async () => {
    if (!activeRutaId) {
      showToast('Seleccione primero una hoja de ruta.', 'warning');
      return;
    }
    const choferId = document.getElementById('select-reasignar-chofer').value || null;

    try {
      const res = await fetch(`${LOGISTICA_API}/rutas/${activeRutaId}/chofer`, {
        method: 'PUT',
        headers: getAuthHeaders(),
        body: JSON.stringify({ choferId })
      });

      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || errData.message || 'Error al asignar chofer a la ruta.');
      }

      showToast('Chofer responsable actualizado para la hoja de ruta.', 'success');
      await loadAllData();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // -------------------------------------------------------------------------
  // PASO 2: AGREGAR DESTINO A LA RUTA
  // -------------------------------------------------------------------------
  document.getElementById('form-agregar-destino-ruta')?.addEventListener('submit', async e => {
    e.preventDefault();
    if (!activeRutaId) {
      showToast('Seleccione primero una hoja de ruta para asociar destinos.', 'warning');
      return;
    }

    const cliente = document.getElementById('destino-cliente').value.trim();
    const direccionTexto = document.getElementById('destino-direccion').value.trim();
    const latitudDestino = parseFloat(document.getElementById('destino-latitud').value);
    const longitudDestino = parseFloat(document.getElementById('destino-longitud').value);

    if (!cliente || !direccionTexto || isNaN(latitudDestino) || isNaN(longitudDestino)) {
      showToast('Complete todos los campos del destino o elija la ubicacion en el mapa.', 'warning');
      return;
    }

    try {
      const res = await fetch(`${LOGISTICA_API}/rutas/${activeRutaId}/destinos`, {
        method: 'POST',
        headers: getAuthHeaders(),
        body: JSON.stringify({ cliente, direccionTexto, latitudDestino, longitudDestino })
      });

      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || errData.message || 'Error al agregar destino.');
      }

      showToast(`Destino "${cliente}" agregado exitosamente a la ruta.`, 'success');
      document.getElementById('destino-cliente').value = '';
      document.getElementById('destino-direccion').value = '';
      document.getElementById('destino-cliente').focus();

      await loadAllData();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // Optimizar ruta activa
  document.getElementById('btn-optimizar-ruta-activa')?.addEventListener('click', async () => {
    if (!activeRutaId) return;

    try {
      const res = await fetch(`${LOGISTICA_API}/rutas/${activeRutaId}/optimizar`, {
        method: 'POST',
        headers: getAuthHeaders()
      });

      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || errData.message || 'Error al optimizar ruta.');
      }

      showToast('Destinos ordenados secuencialmente por cercania geodésica.', 'success');
      await loadAllData();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // Eliminar ruta activa
  document.getElementById('btn-eliminar-ruta-activa')?.addEventListener('click', async () => {
    if (!activeRutaId) return;
    if (!confirm('¿Confirma que desea eliminar esta hoja de ruta completa y todos sus destinos asociados?')) return;

    try {
      const res = await fetch(`${LOGISTICA_API}/rutas/${activeRutaId}`, {
        method: 'DELETE',
        headers: getAuthHeaders()
      });

      if (!res.ok) throw new Error('Error al eliminar la ruta.');

      showToast('Hoja de ruta eliminada exitosamente.', 'success');
      activeRutaId = null;
      await loadAllData();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // Formulario y controles para modificar destino en modal
  document.getElementById('form-editar-destino')?.addEventListener('submit', async e => {
    e.preventDefault();
    if (!activeRutaId) return;

    const despachoId = document.getElementById('edit-despacho-id').value;
    const cliente = document.getElementById('edit-destino-cliente').value.trim();
    const direccionTexto = document.getElementById('edit-destino-direccion').value.trim();
    const latitudDestino = parseFloat(document.getElementById('edit-destino-latitud').value);
    const longitudDestino = parseFloat(document.getElementById('edit-destino-longitud').value);
    const comentarios = document.getElementById('edit-destino-comentarios').value.trim() || null;

    try {
      const res = await fetch(`${LOGISTICA_API}/rutas/${activeRutaId}/destinos/${despachoId}`, {
        method: 'PUT',
        headers: getAuthHeaders(),
        body: JSON.stringify({ cliente, direccionTexto, latitudDestino, longitudDestino, comentarios })
      });

      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || errData.message || 'Error al modificar destino.');
      }

      cerrarModalEditarDestino();
      showToast('Destino modificado exitosamente.', 'success');
      await loadAllData();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  document.getElementById('btn-close-modal-editar-destino')?.addEventListener('click', cerrarModalEditarDestino);
  document.getElementById('btn-cancelar-editar-destino')?.addEventListener('click', cerrarModalEditarDestino);
  document.getElementById('btn-mapa-editar-destino')?.addEventListener('click', () => {
    openMapPickerModal('editar');
  });

  // Formulario: Crear Usuario y Credenciales (RBAC)
  document.getElementById('form-crear-usuario')?.addEventListener('submit', async e => {
    e.preventDefault();
    const email = document.getElementById('input-usr-email').value.trim();
    const password = document.getElementById('input-usr-password').value;
    const nombre = document.getElementById('input-usr-nombre').value.trim();
    const telefono = document.getElementById('input-usr-telefono').value.trim();
    const rol = document.getElementById('select-usr-rol').value;

    try {
      // 1. Registrar usuario en Auth Service
      const resAuth = await fetch(`${AUTH_API}/usuarios`, {
        method: 'POST',
        headers: getAuthHeaders(),
        body: JSON.stringify({ email, password, nombre, telefono, rol })
      });

      if (!resAuth.ok) {
        const errorData = await resAuth.json().catch(() => ({}));
        throw new Error(errorData.error || 'Error al crear usuario.');
      }

      const usuarioCreado = await resAuth.json();

      // 2. Si el rol es CHOFER, sincronizar perfil en Logistica Service con el mismo UUID
      if (rol === 'ROLE_CHOFER') {
        await fetch(`${LOGISTICA_API}/choferes/sincronizar`, {
          method: 'POST',
          headers: getAuthHeaders(),
          body: JSON.stringify({
            id: usuarioCreado.id,
            nombre: usuarioCreado.nombre,
            email: usuarioCreado.email,
            telefono: usuarioCreado.telefono
          })
        });
      }

      showToast(`Usuario ${usuarioCreado.email} creado y sincronizado exitosamente.`, 'success');
      document.getElementById('form-crear-usuario').reset();
      loadUsuarios();
      loadAllData();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // Boton volver a lista en simulador
  document.getElementById('sim-btn-back-to-list')?.addEventListener('click', () => {
    document.getElementById('phone-view-route').style.display = 'none';
    document.getElementById('phone-view-list').style.display = 'flex';
    loadSimulatorDispatches();
  });

  document.getElementById('sim-select-chofer')?.addEventListener('change', () => {
    loadSimulatorDispatches();
  });

  document.getElementById('sim-btn-refresh-list')?.addEventListener('click', () => {
    loadSimulatorDispatches();
  });

  // Simulador: Chofer da consentimiento y comienza el viaje
  document.getElementById('sim-btn-accept-route')?.addEventListener('click', async () => {
    if (!simActiveDespacho) return;

    try {
      const res = await fetch(`${LOGISTICA_API}/despachos/${simActiveDespacho.id}/aceptar-inicio`, {
        method: 'POST',
        headers: getAuthHeaders()
      });
      if (!res.ok) throw new Error('Error al iniciar ruta.');

      showToast('Consentimiento otorgado. Ruta iniciada y streaming activado.', 'success');
      loadAllData();
      openSimulatorRoute(simActiveDespacho.id);
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // Simulador: Chofer cancela la ruta voluntariamente
  document.getElementById('sim-btn-cancel-route')?.addEventListener('click', async () => {
    if (!simActiveDespacho) return;

    const motivo = prompt('Ingrese el motivo de cancelacion de la ruta:');
    if (!motivo) return;

    try {
      stopSimulatedGpsStream();
      const res = await fetch(`${LOGISTICA_API}/despachos/${simActiveDespacho.id}/cancelar`, {
        method: 'POST',
        headers: getAuthHeaders(),
        body: JSON.stringify({ motivo })
      });
      if (!res.ok) throw new Error('Error al cancelar ruta.');

      showToast('Ruta cancelada por el chofer. Streaming de ubicacion cortado.', 'warning');
      loadAllData();
      document.getElementById('sim-btn-back-to-list').click();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // Simulador: Abrir formulario de e-PoD
  document.getElementById('sim-btn-open-pod')?.addEventListener('click', () => {
    document.getElementById('sim-section-in-progress').style.display = 'none';
    document.getElementById('sim-section-pod-form').style.display = 'flex';
  });

  // Simulador: Captura fotográfica con marca de agua
  document.getElementById('sim-photo-box')?.addEventListener('click', () => {
    const canvas = document.createElement('canvas');
    canvas.width = 400;
    canvas.height = 300;
    const ctx = canvas.getContext('2d');

    // Fondo técnico
    const grad = ctx.createLinearGradient(0, 0, 400, 300);
    grad.addColorStop(0, '#0f172a');
    grad.addColorStop(1, '#064e3b');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 400, 300);

    ctx.fillStyle = '#34d399';
    ctx.font = 'bold 16px sans-serif';
    ctx.fillText('EVIDENCIA FOTOGRAFICA DE ENTREGA', 20, 40);

    ctx.fillStyle = '#cbd5e1';
    ctx.font = '13px monospace';
    ctx.fillText('Material: Vidrio Templado 8mm', 20, 80);
    ctx.fillText(`GPS: ${simCurrentLat.toFixed(5)}, ${simCurrentLon.toFixed(5)}`, 20, 110);
    ctx.fillText(`Fecha: ${new Date().toLocaleString()}`, 20, 140);
    ctx.fillText('AlumVid Logistics e-PoD v2.0', 20, 170);

    simPhotoBase64 = canvas.toDataURL('image/jpeg', 0.85);

    document.getElementById('sim-photo-label').style.display = 'none';
    const preview = document.getElementById('sim-photo-preview');
    preview.style.display = 'block';
    preview.src = simPhotoBase64;
    showToast('Fotografia capturada con marca de agua satelital.', 'success');
  });

  // Simulador: Finalizar entrega con e-PoD
  document.getElementById('sim-btn-submit-pod')?.addEventListener('click', async () => {
    if (!simActiveDespacho) return;

    if (!simPhotoBase64) {
      showToast('CP-LOG-01: Debe capturar la fotografia del material entregado.', 'error');
      return;
    }
    if (!simHasDrawn) {
      showToast('CP-LOG-01: El receptor debe firmar en el recuadro tactil.', 'error');
      return;
    }

    const firmaBase64 = simCanvas.toDataURL('image/png');
    const comments = document.getElementById('sim-input-comments').value.trim();

    // Determinar coordenadas de entrega segun selector
    const gpsMode = document.getElementById('sim-delivery-gps-mode').value;
    let finalLat, finalLon;

    if (gpsMode === 'match') {
      finalLat = simActiveDespacho.pedido.latitudDestino;
      finalLon = simActiveDespacho.pedido.longitudDestino;
    } else {
      // Simular desvio a Cumbaya (> 500m)
      finalLat = -0.2035;
      finalLon = -78.4350;
    }

    try {
      stopSimulatedGpsStream();
      const res = await fetch(`${LOGISTICA_API}/despachos/${simActiveDespacho.id}/cerrar-entrega`, {
        method: 'POST',
        headers: getAuthHeaders(),
        body: JSON.stringify({
          fotoPodUrl: simPhotoBase64,
          firmaUrl: firmaBase64,
          latitud: finalLat,
          longitud: finalLon,
          comentarios: comments || 'Entrega completada.'
        })
      });

      if (!res.ok) {
        const errorData = await res.json().catch(() => ({}));
        throw new Error(errorData.message || 'Error al cerrar la entrega.');
      }

      const closed = await res.json();
      if (closed.alertaDesviacion) {
        showToast(`Entrega registrada con ALERTA: Desvio de ${Math.round(closed.desviacionMetros)}m detectado por PostGIS.`, 'warning');
      } else {
        showToast('Entrega finalizada con prueba documental e-PoD valida.', 'success');
      }

      loadAllData();
      document.getElementById('sim-btn-back-to-list').click();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // Modal Evidencia
  document.getElementById('btn-close-modal')?.addEventListener('click', () => {
    document.getElementById('modal-evidence').classList.remove('active');
  });
}

// -------------------------------------------------------------------------
// MODAL DE VISUALIZACION DE EVIDENCIA AUDITADA (e-PoD)
// -------------------------------------------------------------------------
async function viewEvidenceModal(despachoId) {
  try {
    const res = await fetch(`${LOGISTICA_API}/despachos/${despachoId}/evidencia`);
    if (!res.ok) throw new Error('No se pudo obtener la evidencia auditada.');

    const ev = await res.json();
    const body = document.getElementById('modal-evidence-body');

    body.innerHTML = `
      <div style="background: rgba(0,0,0,0.3); padding: 12px; border-radius: 6px;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
          <strong style="color: white; font-size: 0.95rem;">${ev.cliente}</strong>
          ${ev.alertaDesviacion
            ? '<span class="tag-status tag-canceled">Alerta Desvio Espacial > 150m</span>'
            : '<span class="tag-status tag-delivered">Entrega en Destino Verificado</span>'}
        </div>
        <div style="font-size: 0.78rem; color: var(--text-muted);">${ev.direccionCliente}</div>
        <div style="font-size: 0.75rem; color: var(--text-dim); margin-top: 4px;">
          Chofer Responsable: <strong>${ev.choferNombre}</strong> (${ev.choferEmail})
        </div>
      </div>

      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
        <div>
          <label style="font-size: 0.75rem; font-weight: 600; color: var(--text-muted); display: block; margin-bottom: 4px;">Fotografia Registrada:</label>
          <img src="${ev.fotoPodUrl}" alt="Evidencia" style="width: 100%; height: 140px; object-fit: cover; border-radius: 6px; border: 1px solid var(--border-subtle);">
        </div>
        <div>
          <label style="font-size: 0.75rem; font-weight: 600; color: var(--text-muted); display: block; margin-bottom: 4px;">Firma Digital Tactil:</label>
          <img src="${ev.firmaUrl}" alt="Firma" style="width: 100%; height: 140px; object-fit: contain; background: #0a0e17; border-radius: 6px; border: 1px solid var(--border-subtle);">
        </div>
      </div>

      <div style="background: rgba(15, 23, 42, 0.7); padding: 10px; border-radius: 6px; font-size: 0.78rem; display: flex; flex-direction: column; gap: 4px;">
        <div><strong>Destino Oficial:</strong> ${ev.latitudCliente.toFixed(5)}, ${ev.longitudCliente.toFixed(5)}</div>
        <div><strong>Coordenadas Firma GPS:</strong> ${ev.latitudEntrega.toFixed(5)}, ${ev.longitudEntrega.toFixed(5)}</div>
        <div><strong>Desviacion PostGIS:</strong> <strong style="color: ${ev.alertaDesviacion ? '#fb7185' : '#34d399'};">${Math.round(ev.desviacionMetros)} metros</strong></div>
        <div><strong>Fecha y Hora de Cierre:</strong> ${new Date(ev.fechaEntrega).toLocaleString()}</div>
        ${ev.comentarios ? `<div><strong>Observaciones:</strong> <em>${ev.comentarios}</em></div>` : ''}
      </div>
    `;

    document.getElementById('modal-evidence').classList.add('active');
  } catch (err) {
    showToast(err.message, 'error');
  }
}

// Exposicion global para callbacks inline de HTML (onclick)
window.seleccionarRuta = seleccionarRuta;
window.abrirModalEditarDestino = abrirModalEditarDestino;
window.cerrarModalEditarDestino = cerrarModalEditarDestino;
window.eliminarDestinoDeRuta = eliminarDestinoDeRuta;
window.toggleUserStatus = toggleUserStatus;
window.eliminarUsuarioClick = eliminarUsuarioClick;
window.openMapPickerModal = openMapPickerModal;
window.confirmMapPickerSelection = confirmMapPickerSelection;
window.closeMapPickerModal = closeMapPickerModal;
window.openInSimulator = openInSimulator;
window.trackRouteOnMap = trackRouteOnMap;
window.viewEvidenceModal = viewEvidenceModal;
window.openSimulatorRoute = openSimulatorRoute;
