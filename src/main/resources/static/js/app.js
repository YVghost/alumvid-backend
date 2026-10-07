// =========================================================================
// GLASSFLOW LOGISTICS & DRIVER MOBILE SIMULATOR JAVASCRIPT
// =========================================================================

const API_BASE = '/api/v1/logistica';

// State
let allChoferes = [];
let allPedidos = [];
let allDespachos = [];
let currentActiveDespachoForPhone = null;
let currentPhotoBase64 = null;
let isCanvasDrawn = false;

// DOM Elements
const toastContainer = document.getElementById('toast-container');
const viewTitle = document.getElementById('view-title');
const viewSubtitle = document.getElementById('view-subtitle');

// Initialize on Load
document.addEventListener('DOMContentLoaded', () => {
  setupNavigation();
  setupSignatureCanvas();
  setupEventListeners();
  loadAllData();
  updatePhoneClock();
  setInterval(updatePhoneClock, 30000);
});

// -------------------------------------------------------------------------
// NOTIFICATIONS / TOASTS
// -------------------------------------------------------------------------
function showToast(message, type = 'success') {
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  const icon = type === 'success' ? '✅' : type === 'error' ? '❌' : '⚠️';
  toast.innerHTML = `<span>${icon}</span><span>${message}</span>`;
  toastContainer.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    setTimeout(() => toast.remove(), 300);
  }, 4000);
}

// -------------------------------------------------------------------------
// NAVIGATION TABS
// -------------------------------------------------------------------------
function setupNavigation() {
  const navItems = document.querySelectorAll('.nav-item');
  navItems.forEach(item => {
    item.addEventListener('click', () => {
      navItems.forEach(n => n.classList.remove('active'));
      item.classList.add('active');

      const targetTab = item.getAttribute('data-tab');
      document.querySelectorAll('.tab-view').forEach(tab => {
        tab.classList.remove('active');
      });
      document.getElementById(targetTab).classList.add('active');

      // Update header titles
      if (targetTab === 'tab-dashboard') {
        viewTitle.innerText = 'Dashboard Operativo';
        viewSubtitle.innerText = 'Monitoreo de trazabilidad logística y rutas de última milla';
      } else if (targetTab === 'tab-kanban') {
        viewTitle.innerText = 'Tablero Kanban de Despachos';
        viewSubtitle.innerText = 'Supervisión en vivo del estado de entregas y evidencias PoD';
      } else if (targetTab === 'tab-logistica') {
        viewTitle.innerText = 'Gestión de Pedidos y Despachos';
        viewSubtitle.innerText = 'Georreferenciación de clientes y asignación de choferes (HU-04)';
      } else if (targetTab === 'tab-simulator') {
        viewTitle.innerText = 'Simulador de App Móvil del Chofer';
        viewSubtitle.innerText = 'Emulación de smartphone con cámara, firma táctil y sensor GPS (HU-05, HU-06)';
      }
    });
  });

  document.getElementById('btn-quick-order')?.addEventListener('click', () => {
    document.querySelector('.nav-item[data-tab="tab-logistica"]').click();
  });
}

// -------------------------------------------------------------------------
// DATA FETCHING & SYNCHRONIZATION
// -------------------------------------------------------------------------
async function loadAllData() {
  try {
    const [choferesRes, pedidosRes, despachosRes] = await Promise.all([
      fetch(`${API_BASE}/choferes`).then(r => r.json()),
      fetch(`${API_BASE}/pedidos`).then(r => r.json()),
      fetch(`${API_BASE}/despachos`).then(r => r.json())
    ]);

    allChoferes = choferesRes;
    allPedidos = pedidosRes;
    allDespachos = despachosRes;

    updateStatsBar();
    renderDashboardRecent();
    renderKanbanBoard();
    populateSelects();
    populatePhoneDispatches();
  } catch (error) {
    console.error('Error cargando datos:', error);
    showToast('Error de conexión con el backend GlassFlow', 'error');
  }
}

function updateStatsBar() {
  document.getElementById('stat-total-pedidos').innerText = allPedidos.length;
  
  const enRutaCount = allDespachos.filter(d => d.estado === 'EN_RUTA').length;
  document.getElementById('stat-en-ruta').innerText = enRutaCount;

  const entregadosCount = allDespachos.filter(d => d.estado === 'ENTREGADO').length;
  document.getElementById('stat-entregados').innerText = entregadosCount;

  const alertasCount = allDespachos.filter(d => d.alertaDesviacion === true).length;
  document.getElementById('stat-alertas-desvio').innerText = alertasCount;
}

function populateSelects() {
  // Select pedidos pendientes para asignación
  const selectPedido = document.getElementById('select-pedido-asignar');
  const pedidosPendientes = allPedidos.filter(p => p.estado === 'PENDIENTE');
  selectPedido.innerHTML = pedidosPendientes.length === 0 
    ? '<option value="">No hay pedidos pendientes por asignar</option>'
    : '<option value="">-- Seleccionar pedido --</option>' + pedidosPendientes.map(p => `
        <option value="${p.id}">[${p.cliente}] ${p.direccionTexto}</option>
      `).join('');

  // Select choferes para asignación
  const selectChofer = document.getElementById('select-chofer-asignar');
  selectChofer.innerHTML = '<option value="">-- Seleccionar chofer --</option>' + allChoferes.map(c => `
    <option value="${c.id}">${c.nombre} (${c.estadoDisponibilidad})</option>
  `).join('');

  // Select chofer para el simulador móvil
  const simSelectChofer = document.getElementById('sim-select-chofer');
  if (simSelectChofer.options.length <= 1) {
    simSelectChofer.innerHTML = allChoferes.map(c => `
      <option value="${c.id}">${c.nombre}</option>
    `).join('');
  }
}

// -------------------------------------------------------------------------
// DASHBOARD VIEW
// -------------------------------------------------------------------------
function renderDashboardRecent() {
  const container = document.getElementById('dashboard-recent-dispatches');
  if (allDespachos.length === 0) {
    container.innerHTML = '<p style="color: var(--text-muted);">No hay despachos registrados aún. Crea un pedido y asígnalo a un chofer.</p>';
    return;
  }

  container.innerHTML = `
    <div style="overflow-x: auto;">
      <table style="width: 100%; border-collapse: collapse; font-size: 0.88rem;">
        <thead>
          <tr style="text-align: left; border-bottom: 1px solid var(--border-subtle); color: var(--text-muted);">
            <th style="padding: 10px;">Cliente</th>
            <th style="padding: 10px;">Dirección</th>
            <th style="padding: 10px;">Chofer</th>
            <th style="padding: 10px;">Estado</th>
            <th style="padding: 10px;">Auditoría PostGIS</th>
            <th style="padding: 10px;">Acción</th>
          </tr>
        </thead>
        <tbody>
          ${allDespachos.slice(0, 8).map(d => `
            <tr style="border-bottom: 1px solid rgba(255,255,255,0.04);">
              <td style="padding: 12px 10px; font-weight: 700;">${d.pedido.cliente}</td>
              <td style="padding: 12px 10px; color: var(--text-muted);">${d.pedido.direccionTexto}</td>
              <td style="padding: 12px 10px;">${d.chofer.nombre}</td>
              <td style="padding: 12px 10px;">
                <span class="card-driver-tag ${d.estado === 'ENTREGADO' ? 'tag-success' : ''}">
                  ${d.estado}
                </span>
              </td>
              <td style="padding: 12px 10px;">
                ${d.estado === 'ENTREGADO' 
                  ? (d.alertaDesviacion 
                      ? `<span class="card-driver-tag tag-alert">⚠️ Desvío: ${Math.round(d.desviacionMetros)}m</span>`
                      : `<span class="card-driver-tag tag-success">✓ En sitio (${Math.round(d.desviacionMetros)}m)</span>`)
                  : '<span style="color: var(--text-dim);">-</span>'}
              </td>
              <td style="padding: 12px 10px;">
                ${d.estado === 'ENTREGADO'
                  ? `<button class="btn btn-outline" style="padding: 4px 8px; font-size: 0.78rem;" onclick="viewEvidenceModal('${d.id}')">Ver e-PoD</button>`
                  : `<button class="btn btn-primary" style="padding: 4px 8px; font-size: 0.78rem;" onclick="switchToPhone('${d.chofer.id}')">Atender</button>`}
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

// -------------------------------------------------------------------------
// KANBAN BOARD VIEW
// -------------------------------------------------------------------------
function renderKanbanBoard() {
  const pendientesCol = document.getElementById('kanban-list-pendientes');
  const enRutaCol = document.getElementById('kanban-list-enruta');
  const entregadosCol = document.getElementById('kanban-list-entregados');

  const pendientes = allDespachos.filter(d => d.estado === 'PENDIENTE');
  const enRuta = allDespachos.filter(d => d.estado === 'EN_RUTA');
  const entregados = allDespachos.filter(d => d.estado === 'ENTREGADO');

  document.getElementById('count-kanban-pendientes').innerText = pendientes.length;
  document.getElementById('count-kanban-enruta').innerText = enRuta.length;
  document.getElementById('count-kanban-entregados').innerText = entregados.length;

  pendientesCol.innerHTML = pendientes.length === 0
    ? '<p style="color: var(--text-dim); font-size: 0.85rem; text-align: center; margin-top: 2rem;">No hay despachos pendientes</p>'
    : pendientes.map(d => createKanbanCardHtml(d)).join('');

  enRutaCol.innerHTML = enRuta.length === 0
    ? '<p style="color: var(--text-dim); font-size: 0.85rem; text-align: center; margin-top: 2rem;">No hay vehículos en ruta</p>'
    : enRuta.map(d => createKanbanCardHtml(d)).join('');

  entregadosCol.innerHTML = entregados.length === 0
    ? '<p style="color: var(--text-dim); font-size: 0.85rem; text-align: center; margin-top: 2rem;">No hay entregas registradas</p>'
    : entregados.map(d => createKanbanCardHtml(d)).join('');
}

function createKanbanCardHtml(d) {
  const shortId = d.id.substring(0, 8);
  const isDelivered = d.estado === 'ENTREGADO';
  const isEnRuta = d.estado === 'EN_RUTA';

  let actionHtml = '';
  if (d.estado === 'PENDIENTE') {
    actionHtml = `
      <button class="btn btn-primary" style="width: 100%; font-size: 0.8rem; padding: 8px;" onclick="handleStartRoute('${d.id}')">
        Iniciar Ruta ➔
      </button>
    `;
  } else if (isEnRuta) {
    actionHtml = `
      <button class="btn btn-outline" style="width: 100%; font-size: 0.8rem; padding: 8px;" onclick="switchToPhone('${d.chofer.id}')">
        📱 Abrir en App del Chofer
      </button>
    `;
  } else if (isDelivered) {
    actionHtml = `
      <button class="btn btn-outline" style="width: 100%; font-size: 0.8rem; padding: 8px;" onclick="viewEvidenceModal('${d.id}')">
        📄 Ver Evidencia (e-PoD)
      </button>
    `;
  }

  return `
    <div class="kanban-card">
      <div class="card-header-row">
        <span class="card-order-id">#${shortId}</span>
        ${isDelivered && d.alertaDesviacion 
          ? '<span class="card-driver-tag tag-alert">⚠️ Alerta >500m</span>' 
          : isDelivered 
            ? '<span class="card-driver-tag tag-success">✓ Verificado</span>' 
            : `<span class="card-driver-tag">${d.estado}</span>`}
      </div>
      <div class="card-client-name">${d.pedido.cliente}</div>
      <div class="card-address">📍 ${d.pedido.direccionTexto}</div>
      <div style="font-size: 0.78rem; color: var(--text-muted);">
        👤 Chofer: <strong style="color: var(--text-main);">${d.chofer.nombre}</strong>
      </div>
      ${isDelivered ? `
        <div style="font-size: 0.75rem; color: var(--text-dim); background: rgba(0,0,0,0.25); padding: 6px; border-radius: 4px;">
          Distancia calculada: <strong>${Math.round(d.desviacionMetros)} metros</strong>
        </div>
      ` : ''}
      <div style="margin-top: 4px;">
        ${actionHtml}
      </div>
    </div>
  `;
}

// Iniciar ruta
async function handleStartRoute(despachoId) {
  try {
    const res = await fetch(`${API_BASE}/despachos/${despachoId}/iniciar`, { method: 'PATCH' });
    if (!res.ok) throw new Error('Error al iniciar ruta');
    showToast('Ruta iniciada. El pedido se encuentra en trayecto.', 'success');
    loadAllData();
  } catch (error) {
    showToast(error.message, 'error');
  }
}

// -------------------------------------------------------------------------
// SIMULADOR DE APP MOVIL DEL CHOFER (HU-05, HU-06, CP-LOG-01, CP-LOG-02)
// -------------------------------------------------------------------------
function switchToPhone(choferId) {
  document.querySelector('.nav-item[data-tab="tab-simulator"]').click();
  const simSelect = document.getElementById('sim-select-chofer');
  simSelect.value = choferId;
  populatePhoneDispatches();
}

function updatePhoneClock() {
  const now = new Date();
  const hours = String(now.getHours()).padStart(2, '0');
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const clockEl = document.getElementById('phone-clock');
  if (clockEl) clockEl.innerText = `${hours}:${minutes}`;
}

async function populatePhoneDispatches() {
  const choferId = document.getElementById('sim-select-chofer').value;
  const container = document.getElementById('phone-dispatches-container');

  if (!choferId) {
    container.innerHTML = '<p style="color: var(--text-dim); text-align: center;">Seleccione un chofer para ver sus entregas.</p>';
    return;
  }

  try {
    const res = await fetch(`${API_BASE}/choferes/${choferId}/despachos-hoy`);
    const despachos = await res.json();

    if (despachos.length === 0) {
      container.innerHTML = `
        <div style="text-align: center; padding: 3rem 1rem;">
          <div style="font-size: 2.5rem; margin-bottom: 8px;">🎉</div>
          <div style="font-weight: 700; color: var(--text-main);">Sin entregas pendientes</div>
          <div style="font-size: 0.78rem; color: var(--text-dim); margin-top: 4px;">No tienes despachos asignados hoy.</div>
        </div>
      `;
      return;
    }

    container.innerHTML = despachos.map(d => `
      <div style="background: #1e293b; border: 1px solid rgba(255,255,255,0.08); border-radius: 8px; padding: 12px; display: flex; flex-direction: column; gap: 6px; cursor: pointer;"
           onclick="openDeliveryInPhone('${d.id}')">
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <span style="font-size: 0.7rem; color: var(--primary); font-weight: 700;">PEDIDO #${d.id.substring(0, 6)}</span>
          <span class="card-driver-tag ${d.estado === 'ENTREGADO' ? 'tag-success' : ''}" style="font-size: 0.68rem; padding: 2px 6px;">
            ${d.estado}
          </span>
        </div>
        <div style="font-size: 0.9rem; font-weight: 700; color: white;">${d.pedido.cliente}</div>
        <div style="font-size: 0.75rem; color: var(--text-muted);">📍 ${d.pedido.direccionTexto}</div>
        ${d.estado !== 'ENTREGADO' ? `
          <button class="btn btn-primary" style="margin-top: 4px; padding: 6px 10px; font-size: 0.75rem;" onclick="event.stopPropagation(); openDeliveryInPhone('${d.id}')">
            Abrir y Firmar ➔
          </button>
        ` : `
          <div style="font-size: 0.72rem; color: #34d399; font-weight: 600;">✓ Entrega Completada</div>
        `}
      </div>
    `).join('');
  } catch (error) {
    console.error('Error cargando despachos del chofer:', error);
  }
}

function openDeliveryInPhone(despachoId) {
  const despacho = allDespachos.find(d => d.id === despachoId);
  if (!despacho) return;

  currentActiveDespachoForPhone = despacho;

  document.getElementById('phone-delivery-order-id').innerText = `PEDIDO #${despacho.id.substring(0, 8)}`;
  document.getElementById('phone-delivery-client').innerText = despacho.pedido.cliente;
  document.getElementById('phone-delivery-address').innerText = `📍 ${despacho.pedido.direccionTexto}`;

  // Reset signature canvas and photo
  clearSignatureCanvas();
  resetPhotoUploader();

  document.getElementById('phone-view-list').style.display = 'none';
  document.getElementById('phone-view-delivery').style.display = 'flex';
}

function resetPhotoUploader() {
  currentPhotoBase64 = null;
  const label = document.getElementById('photo-uploader-label');
  const preview = document.getElementById('photo-preview-element');
  label.style.display = 'block';
  preview.style.display = 'none';
  preview.src = '';
}

// -------------------------------------------------------------------------
// CANVAS SIGNATURE COMPONENT (FIRMA TÁCTIL DIGITAL)
// -------------------------------------------------------------------------
let canvas, ctx;
let isDrawing = false;

function setupSignatureCanvas() {
  canvas = document.getElementById('signature-canvas');
  if (!canvas) return;
  ctx = canvas.getContext('2d');

  ctx.strokeStyle = '#60a5fa';
  ctx.lineWidth = 2.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // Mouse events
  canvas.addEventListener('mousedown', startDrawing);
  canvas.addEventListener('mousemove', draw);
  canvas.addEventListener('mouseup', stopDrawing);
  canvas.addEventListener('mouseleave', stopDrawing);

  // Touch events for mobile
  canvas.addEventListener('touchstart', (e) => {
    e.preventDefault();
    const touch = e.touches[0];
    const mouseEvent = new MouseEvent('mousedown', {
      clientX: touch.clientX,
      clientY: touch.clientY
    });
    canvas.dispatchEvent(mouseEvent);
  });

  canvas.addEventListener('touchmove', (e) => {
    e.preventDefault();
    const touch = e.touches[0];
    const mouseEvent = new MouseEvent('mousemove', {
      clientX: touch.clientX,
      clientY: touch.clientY
    });
    canvas.dispatchEvent(mouseEvent);
  });

  canvas.addEventListener('touchend', (e) => {
    e.preventDefault();
    canvas.dispatchEvent(new MouseEvent('mouseup', {}));
  });

  document.getElementById('btn-clear-canvas')?.addEventListener('click', clearSignatureCanvas);
}

function getCanvasCoordinates(e) {
  const rect = canvas.getBoundingClientRect();
  return {
    x: e.clientX - rect.left,
    y: e.clientY - rect.top
  };
}

function startDrawing(e) {
  isDrawing = true;
  isCanvasDrawn = true;
  const pos = getCanvasCoordinates(e);
  ctx.beginPath();
  ctx.moveTo(pos.x, pos.y);
}

function draw(e) {
  if (!isDrawing) return;
  const pos = getCanvasCoordinates(e);
  ctx.lineTo(pos.x, pos.y);
  ctx.stroke();
}

function stopDrawing() {
  if (isDrawing) {
    ctx.closePath();
    isDrawing = false;
  }
}

function clearSignatureCanvas() {
  if (!ctx || !canvas) return;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  isCanvasDrawn = false;
}

// -------------------------------------------------------------------------
// EVENT LISTENERS & FORM SUBMISSIONS
// -------------------------------------------------------------------------
function setupEventListeners() {
  // Refresh data buttons
  document.getElementById('btn-refresh-data')?.addEventListener('click', () => {
    loadAllData();
    showToast('Datos sincronizados con PostGIS', 'success');
  });

  document.getElementById('btn-sync-kanban')?.addEventListener('click', () => {
    loadAllData();
    showToast('Kanban sincronizado', 'success');
  });

  document.getElementById('sim-btn-refresh-phone')?.addEventListener('click', populatePhoneDispatches);

  // Back to dispatches list in phone
  document.getElementById('sim-btn-back-to-list')?.addEventListener('click', () => {
    document.getElementById('phone-view-delivery').style.display = 'none';
    document.getElementById('phone-view-list').style.display = 'flex';
    populatePhoneDispatches();
  });

  // Simulator driver select change
  document.getElementById('sim-select-chofer')?.addEventListener('change', populatePhoneDispatches);

  // Ubicación predefinida selector
  document.getElementById('select-ubicacion-predefinida')?.addEventListener('change', (e) => {
    const val = e.target.value;
    if (val !== 'custom') {
      const [lat, lon] = val.split(',');
      document.getElementById('input-latitud').value = lat;
      document.getElementById('input-longitud').value = lon;
    }
  });

  // Toggle GPS switch listener
  const toggleGps = document.getElementById('sim-toggle-gps');
  const gpsLabel = document.getElementById('sim-gps-status-label');
  toggleGps?.addEventListener('change', (e) => {
    if (e.target.checked) {
      gpsLabel.innerText = '🟢 GPS Activo';
      gpsLabel.style.color = '#34d399';
    } else {
      gpsLabel.innerText = '🔴 GPS Desactivado';
      gpsLabel.style.color = '#f43f5e';
    }
  });

  // Simular captura de cámara (PoD)
  document.getElementById('phone-photo-uploader')?.addEventListener('click', () => {
    // Generar imagen simulada de vidrio entregado con marca de agua timestamp
    const dummyCanvas = document.createElement('canvas');
    dummyCanvas.width = 400;
    dummyCanvas.height = 300;
    const dctx = dummyCanvas.getContext('2d');

    // Fondo simulado de panel de vidrio templado
    const grad = dctx.createLinearGradient(0, 0, 400, 300);
    grad.addColorStop(0, '#0f172a');
    grad.addColorStop(0.5, '#1e293b');
    grad.addColorStop(1, '#065f46');
    dctx.fillStyle = grad;
    dctx.fillRect(0, 0, 400, 300);

    dctx.fillStyle = '#10b981';
    dctx.font = 'bold 18px sans-serif';
    dctx.fillText('✓ EVIDENCIA DE ENTREGA (PoD)', 25, 45);

    dctx.fillStyle = '#94a3b8';
    dctx.font = '14px monospace';
    dctx.fillText('Vidrio Templado 6mm - Sin Daños', 25, 80);
    dctx.fillText('GPS: -0.1807, -78.4678', 25, 110);
    dctx.fillText(`Timestamp: ${new Date().toLocaleString()}`, 25, 140);
    dctx.fillText('Trazabilidad GlassFlow v1.0', 25, 170);

    currentPhotoBase64 = dummyCanvas.toDataURL('image/jpeg', 0.85);

    const label = document.getElementById('photo-uploader-label');
    const preview = document.getElementById('photo-preview-element');
    label.style.display = 'none';
    preview.style.display = 'block';
    preview.src = currentPhotoBase64;

    showToast('Foto de entrega capturada con éxito', 'success');
  });

  // Crear Pedido Form
  document.getElementById('form-crear-pedido')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const cliente = document.getElementById('input-cliente').value.trim();
    const direccion = document.getElementById('input-direccion').value.trim();
    const lat = parseFloat(document.getElementById('input-latitud').value);
    const lon = parseFloat(document.getElementById('input-longitud').value);

    try {
      const res = await fetch(`${API_BASE}/pedidos`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          cliente,
          direccionTexto: direccion,
          latitud: lat,
          longitud: lon
        })
      });

      if (!res.ok) throw new Error('Error al registrar pedido');
      showToast('Pedido registrado con georreferenciación PostGIS', 'success');
      document.getElementById('form-crear-pedido').reset();
      loadAllData();
    } catch (error) {
      showToast(error.message, 'error');
    }
  });

  // Asignar Despacho Form (HU-04)
  document.getElementById('form-asignar-despacho')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const pedidoId = document.getElementById('select-pedido-asignar').value;
    const choferId = document.getElementById('select-chofer-asignar').value;

    if (!pedidoId || !choferId) {
      showToast('Debe seleccionar pedido y chofer', 'warning');
      return;
    }

    try {
      const res = await fetch(`${API_BASE}/despachos/asignar`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pedidoId, choferId })
      });

      if (!res.ok) throw new Error('Error al asignar despacho');
      showToast('Hoja de ruta asignada al chofer exitosamente', 'success');
      loadAllData();
      // Switch to Kanban
      document.querySelector('.nav-item[data-tab="tab-kanban"]').click();
    } catch (error) {
      showToast(error.message, 'error');
    }
  });

  // Cierre de entrega en Smartphone del Chofer (HU-05, HU-06, CP-LOG-01, CP-LOG-02)
  document.getElementById('btn-phone-submit-delivery')?.addEventListener('click', async () => {
    if (!currentActiveDespachoForPhone) {
      showToast('No hay un despacho activo seleccionado', 'error');
      return;
    }

    // 1. CP-LOG-01: Validar si el GPS está apagado
    const isGpsActive = document.getElementById('sim-toggle-gps').checked;
    if (!isGpsActive) {
      // Desplegar modal nativo de permisos GPS (tal como exige CP-LOG-01)
      document.getElementById('modal-gps-alert').classList.add('active');
      return;
    }

    // 2. HU-05: Validar foto PoD
    if (!currentPhotoBase64) {
      showToast('Debe adjuntar la fotografía del material entregado (PoD)', 'error');
      return;
    }

    // 3. HU-05: Validar firma digital
    if (!isCanvasDrawn) {
      showToast('El cliente debe estampar su firma en el recuadro táctil', 'error');
      return;
    }

    const firmaBase64 = canvas.toDataURL('image/png');
    const comentarios = document.getElementById('phone-input-comentarios').value.trim();

    // 4. HU-06 y CP-LOG-02: Calcular coordenadas GPS según modo de simulación
    const gpsMode = document.getElementById('sim-gps-mode').value;
    let entregaLat, entregaLon;

    if (gpsMode === 'match') {
      // Ubicación coincidente con el destino del cliente (< 10 metros)
      entregaLat = currentActiveDespachoForPhone.pedido.latitudDestino;
      entregaLon = currentActiveDespachoForPhone.pedido.longitudDestino;
    } else {
      // Desvío simulado (> 500 metros) - Cumbayá vs Quito Norte
      entregaLat = -0.2035;
      entregaLon = -78.4350;
    }

    try {
      const res = await fetch(`${API_BASE}/despachos/${currentActiveDespachoForPhone.id}/cerrar-entrega`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fotoPodUrl: currentPhotoBase64,
          firmaUrl: firmaBase64,
          latitud: entregaLat,
          longitud: entregaLon,
          comentarios: comentarios || 'Entrega verificada por el chofer.'
        })
      });

      if (!res.ok) {
        const errorData = await res.json().catch(() => ({}));
        throw new Error(errorData.message || 'Error cerrando la entrega');
      }

      const closedDispatch = await res.json();

      if (closedDispatch.alertaDesviacion) {
        showToast(`⚠️ Entrega completada con ALERTA: Desvío de ${Math.round(closedDispatch.desviacionMetros)}m detectado por PostGIS`, 'warning');
      } else {
        showToast('✓ Despacho entregado y prueba e-PoD registrada con éxito', 'success');
      }

      // Regresar a la lista de despachos
      document.getElementById('phone-view-delivery').style.display = 'none';
      document.getElementById('phone-view-list').style.display = 'flex';

      loadAllData();
    } catch (error) {
      showToast(error.message, 'error');
    }
  });

  // Modal GPS alert buttons
  document.getElementById('btn-gps-alert-cancel')?.addEventListener('click', () => {
    document.getElementById('modal-gps-alert').classList.remove('active');
  });

  document.getElementById('btn-gps-alert-enable')?.addEventListener('click', () => {
    document.getElementById('sim-toggle-gps').checked = true;
    document.getElementById('sim-toggle-gps').dispatchEvent(new Event('change'));
    document.getElementById('modal-gps-alert').classList.remove('active');
    showToast('GPS activado correctamente', 'success');
  });

  // Close evidence modal
  document.getElementById('btn-close-modal')?.addEventListener('click', () => {
    document.getElementById('modal-evidence').classList.remove('active');
  });
}

// -------------------------------------------------------------------------
// MODAL DE AUDITORÍA e-PoD (VER FOTO, FIRMA Y DESVÍO)
// -------------------------------------------------------------------------
async function viewEvidenceModal(despachoId) {
  try {
    const res = await fetch(`${API_BASE}/despachos/${despachoId}/evidencia`);
    if (!res.ok) throw new Error('No se pudo cargar la evidencia');
    const ev = await res.json();

    const body = document.getElementById('modal-evidence-body');
    body.innerHTML = `
      <div style="background: rgba(0,0,0,0.3); padding: 12px; border-radius: 8px;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
          <strong style="color: white; font-size: 1.05rem;">${ev.cliente}</strong>
          ${ev.alertaDesviacion 
            ? '<span class="card-driver-tag tag-alert">⚠️ Alerta Desvío Geográfico >500m</span>' 
            : '<span class="card-driver-tag tag-success">✓ Entrega en Ubicación Verificada</span>'}
        </div>
        <div style="font-size: 0.8rem; color: var(--text-muted);">📍 ${ev.direccionCliente}</div>
        <div style="font-size: 0.8rem; color: var(--text-dim); margin-top: 4px;">
          Entregado por: <strong>${ev.choferNombre}</strong> (${ev.choferEmail})
        </div>
      </div>

      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
        <div>
          <label style="font-size: 0.78rem; font-weight: 600; color: var(--text-muted); display: block; margin-bottom: 4px;">Fotografía PoD:</label>
          <img src="${ev.fotoPodUrl}" alt="Foto PoD" style="width: 100%; height: 160px; object-fit: cover; border-radius: 8px; border: 1px solid var(--border-subtle);">
        </div>
        <div>
          <label style="font-size: 0.78rem; font-weight: 600; color: var(--text-muted); display: block; margin-bottom: 4px;">Firma del Receptor:</label>
          <img src="${ev.firmaUrl}" alt="Firma" style="width: 100%; height: 160px; object-fit: contain; background: #0b0f19; border-radius: 8px; border: 1px solid var(--border-subtle);">
        </div>
      </div>

      <div style="background: rgba(15, 23, 42, 0.7); padding: 12px; border-radius: 8px; font-size: 0.8rem; display: flex; flex-direction: column; gap: 4px;">
        <div>🌐 <strong>Coordenadas Destino:</strong> ${ev.latitudCliente.toFixed(5)}, ${ev.longitudCliente.toFixed(5)}</div>
        <div>📍 <strong>Coordenadas de Firma GPS:</strong> ${ev.latitudEntrega.toFixed(5)}, ${ev.longitudEntrega.toFixed(5)}</div>
        <div>📏 <strong>Desviación Espacial (PostGIS):</strong> <strong style="color: ${ev.alertaDesviacion ? '#fb7185' : '#34d399'};">${Math.round(ev.desviacionMetros)} metros</strong></div>
        <div>🕒 <strong>Fecha/Hora de Cierre:</strong> ${new Date(ev.fechaEntrega).toLocaleString()}</div>
        ${ev.comentarios ? `<div>💬 <strong>Observaciones:</strong> <em>${ev.comentarios}</em></div>` : ''}
      </div>
    `;

    document.getElementById('modal-evidence').classList.add('active');
  } catch (error) {
    showToast(error.message, 'error');
  }
}
