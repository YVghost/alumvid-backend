// =========================================================================
// GLASSFLOW LOGISTICS & FLEET MANAGEMENT PLATFORM - JAVASCRIPT
// =========================================================================

const AUTH_API = '/api/v1/auth';
const LOGISTICA_API = '/api/v1/logistica';
const WS_ENDPOINT = 'http://localhost:8082/ws-logistica';

// Estado global de la aplicacion
let authToken = localStorage.getItem('glassflow_token') || null;
let currentUser = null;
let allUsuarios = [];
let allChoferes = [];
let allPedidos = [];
let allDespachos = [];

// Google Maps & Telemetria
let googleMap = null;
let activeDriverMarker = null;
let destinationMarkers = [];
let stompClient = null;
let currentTrackingDespachoId = null;

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

  await authenticateInitialAdmin();
  initGoogleMap();
  connectWebSocket();
  await loadAllData();
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
// AUTENTICACION DE ADMINISTRADOR (JWT)
// -------------------------------------------------------------------------
async function authenticateInitialAdmin() {
  try {
    const res = await fetch(`${AUTH_API}/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'admin@glassflow.com',
        password: 'GlassFlowAdmin2026!'
      })
    });

    if (res.ok) {
      const data = await res.json();
      authToken = data.token;
      localStorage.setItem('glassflow_token', authToken);
      currentUser = data;
      document.getElementById('logged-user-email').innerText = data.email;
    }
  } catch (err) {
    console.warn('Inicio de sesion inicial automatico no completado:', err.message);
  }
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
    const [pedidosRes, choferesRes, despachosRes] = await Promise.all([
      fetch(`${LOGISTICA_API}/pedidos`).then(r => r.json()),
      fetch(`${LOGISTICA_API}/choferes`).then(r => r.json()),
      fetch(`${LOGISTICA_API}/despachos`).then(r => r.json())
    ]);

    allPedidos = pedidosRes;
    allChoferes = choferesRes;
    allDespachos = despachosRes;

    updateStats();
    renderKanban();
    populateSelects();
    renderDestinationMarkersOnMap();
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

function populateSelects() {
  // Pedidos pendientes
  const selectPedido = document.getElementById('select-pedido-disponible');
  const pedidosPendientes = allPedidos.filter(p => p.estado === 'PENDIENTE');
  selectPedido.innerHTML = pedidosPendientes.length === 0
    ? '<option value="">No hay pedidos pendientes de asignacion</option>'
    : '<option value="">-- Seleccionar pedido --</option>' + pedidosPendientes.map(p => `
        <option value="${p.id}">[${p.cliente}] ${p.direccionTexto}</option>
      `).join('');

  // Choferes disponibles
  const selectChofer = document.getElementById('select-chofer-disponible');
  selectChofer.innerHTML = '<option value="">-- Seleccionar chofer --</option>' + allChoferes.map(c => `
    <option value="${c.id}">${c.nombre} (${c.estadoDisponibilidad})</option>
  `).join('');

  // Choferes en simulador
  const simSelect = document.getElementById('sim-select-chofer');
  if (simSelect.options.length <= 1) {
    simSelect.innerHTML = allChoferes.map(c => `
      <option value="${c.id}">${c.nombre}</option>
    `).join('');
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
  const shortId = d.id.substring(0, 8);

  let statusBadge = '';
  let actions = '';

  if (status === 'PENDIENTE') {
    statusBadge = '<span class="tag-status tag-pending">Pendiente Consentimiento</span>';
    actions = `
      <button class="btn btn-outline" style="width: 100%; font-size: 0.75rem; padding: 6px;" onclick="openInSimulator('${d.chofer.id}', '${d.id}')">
        Ver en App del Chofer
      </button>
    `;
  } else if (status === 'EN_CURSO') {
    statusBadge = '<span class="tag-status tag-en-curso">En Transito [GPS ON]</span>';
    actions = `
      <button class="btn btn-primary" style="width: 100%; font-size: 0.75rem; padding: 6px;" onclick="trackRouteOnMap('${d.id}', ${d.pedido.latitudDestino}, ${d.pedido.longitudDestino})">
        Rastrear en Google Maps
      </button>
    `;
  } else if (status === 'ENTREGADO') {
    statusBadge = d.alertaDesviacion
      ? `<span class="tag-status tag-canceled">Alerta Desvio: ${Math.round(d.desviacionMetros)}m</span>`
      : `<span class="tag-status tag-delivered">Verificado (${Math.round(d.desviacionMetros)}m)</span>`;
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
      <div class="card-client-name">${d.pedido.cliente}</div>
      <div class="card-address">Destino: ${d.pedido.direccionTexto}</div>
      <div style="font-size: 0.75rem; color: var(--text-muted);">
        Chofer: <strong style="color: var(--text-main);">${d.chofer.nombre}</strong>
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

    tbody.innerHTML = allUsuarios.map(u => `
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
        <td>
          <button class="btn btn-outline" style="padding: 4px 8px; font-size: 0.72rem;" onclick="toggleUserStatus('${u.id}', ${!u.activo})">
            ${u.activo ? 'Suspender' : 'Activar'}
          </button>
        </td>
      </tr>
    `).join('');
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

  // Formulario: Crear Pedido
  document.getElementById('form-crear-pedido')?.addEventListener('submit', async e => {
    e.preventDefault();
    const cliente = document.getElementById('input-pedido-cliente').value.trim();
    const direccion = document.getElementById('input-pedido-direccion').value.trim();
    const latitud = parseFloat(document.getElementById('input-pedido-latitud').value);
    const longitud = parseFloat(document.getElementById('input-pedido-longitud').value);

    try {
      const res = await fetch(`${LOGISTICA_API}/pedidos`, {
        method: 'POST',
        headers: getAuthHeaders(),
        body: JSON.stringify({ cliente, direccionTexto: direccion, latitud, longitud })
      });
      if (!res.ok) throw new Error('Error al registrar pedido.');

      showToast('Pedido registrado con georreferenciacion PostGIS.', 'success');
      document.getElementById('form-crear-pedido').reset();
      loadAllData();
    } catch (err) {
      showToast(err.message, 'error');
    }
  });

  // Formulario: Asignar Hoja de Ruta
  document.getElementById('form-asignar-ruta')?.addEventListener('submit', async e => {
    e.preventDefault();
    const pedidoId = document.getElementById('select-pedido-disponible').value;
    const choferId = document.getElementById('select-chofer-disponible').value;

    if (!pedidoId || !choferId) {
      showToast('Debe seleccionar pedido y chofer.', 'warning');
      return;
    }

    try {
      const res = await fetch(`${LOGISTICA_API}/despachos/asignar`, {
        method: 'POST',
        headers: getAuthHeaders(),
        body: JSON.stringify({ pedidoId, choferId })
      });
      if (!res.ok) throw new Error('Error al asignar hoja de ruta.');

      showToast('Ruta asignada. Chofer notificado para dar consentimiento.', 'success');
      loadAllData();
      document.querySelector('.nav-item[data-tab="tab-kanban"]').click();
    } catch (err) {
      showToast(err.message, 'error');
    }
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
    ctx.fillText('GlassFlow Logistics e-PoD v2.0', 20, 170);

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
