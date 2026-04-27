// ── 新增/编辑出入库记录 ──
import { api } from '../api.js';
import { store } from '../state.js';
import { esc } from './dashboard.js';

let editingId = null;
let editingRecord = null;

export async function renderMovementForm(id = null) {
  const main = document.getElementById('mainContent');
  main.innerHTML = '<div class="page-loader"><div class="spinner"></div></div>';
  editingId = id;

  document.querySelectorAll('.nav-link').forEach(a => {
    a.classList.toggle('active', a.getAttribute('data-route') === 'movements');
  });

  const warehouses = await store.loadWarehouses();

  if (id) {
    try {
      editingRecord = await api.get('/api/movements/' + id);
    } catch (e) {
      main.innerHTML = '<div class="empty-state"><p>加载失败: ' + esc(e.message) + '</p></div>';
      return;
    }
  } else {
    editingRecord = null;
  }

  const r = editingRecord;
  const isEdit = !!r;
  const readonly = isEdit ? 'readonly' : '';

  main.innerHTML = `
    <div class="page-title">
      <i class="fa-solid fa-${isEdit ? 'pen-to-square' : 'plus'}" style="color:var(--teal)"></i>
      ${isEdit ? '编辑记录' : '新增记录'}
      ${isEdit ? '<span class="sub">' + esc(r.partnerName) + '</span>' : ''}
    </div>

    <form id="movementForm" onsubmit="return false" style="max-width:800px">

      <!-- 仓库选择 & 类型 -->
      <div class="card" style="margin-bottom:16px">
        <div class="card-body">
          <div class="form-grid cols-2">
            <div class="form-group">
              <label class="form-label">目标仓库 <span class="required">*</span></label>
              <select class="form-select" id="fWarehouseId" ${isEdit ? 'disabled' : ''}>
                <option value="">请选择仓库</option>
                ${warehouses.map(w => `<option value="${w.id}" ${r && r.warehouseId === w.id ? 'selected' : ''}>${esc(w.name)}</option>`).join('')}
              </select>
            </div>
            <div class="form-group">
              <label class="form-label">单据类型 <span class="required">*</span></label>
              <div class="segment-group" id="segType">
                <button type="button" class="segment-btn" data-type="inbound" ${isEdit ? 'disabled' : ''}>📥 入库</button>
                <button type="button" class="segment-btn" data-type="outbound" ${isEdit ? 'disabled' : ''}>📤 出库</button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- 交易信息 -->
      <div class="card" style="margin-bottom:16px">
        <div class="card-header">交易信息</div>
        <div class="card-body">
          <div class="form-grid cols-2">
            <div class="form-group">
              <label class="form-label">交易对象 <span class="required">*</span></label>
              <input class="form-input" id="fPartnerName" value="${esc(r ? r.partnerName : '')}" ${readonly} placeholder="供应商/客户名称">
            </div>
            <div class="form-group">
              <label class="form-label">送货人</label>
              <input class="form-input" id="fDeliveryPerson" value="${esc(r ? r.deliveryPerson||'' : '')}" placeholder="送货人姓名（可选）">
            </div>
            <div class="form-group">
              <label class="form-label">颜色</label>
              <input class="form-input" id="fColor" value="${esc(r ? r.color||'' : '')}" ${readonly} placeholder="如：白色、黑色">
            </div>
            <div class="form-group">
              <label class="form-label">品种</label>
              <input class="form-input" id="fVariety" value="${esc(r ? r.variety||'' : '')}" ${readonly} placeholder="如：绵羊毛">
            </div>
          </div>
        </div>
      </div>

      <!-- 重量 & 金额 -->
      <div class="card" style="margin-bottom:16px">
        <div class="card-header">重量与金额</div>
        <div class="card-body">
          <div class="form-grid cols-3">
            <div class="form-group">
              <label class="form-label">毛重 (kg) <span class="required">*</span></label>
              <input class="form-input mono" id="fGrossWeight" type="number" step="0.1" min="0"
                     value="${r ? (r.grossWeight||0) : ''}" placeholder="地磅读数" oninput="recalc()">
            </div>
            <div class="form-group">
              <label class="form-label">扣皮 (kg)</label>
              <input class="form-input mono" id="fTareWeight" type="number" step="0.1" min="0"
                     value="${r ? (r.tareWeight||0) : '0'}" placeholder="去皮重量，默认 0" oninput="recalc()">
            </div>
            <div class="form-group">
              <label class="form-label">总件数</label>
              <input class="form-input mono" id="fTotalPieces" type="number" step="1" min="0"
                     value="${r ? (r.totalPieces||'') : ''}" placeholder="件数（可选）">
            </div>
            <div class="form-group">
              <label class="form-label">单价 (元/吨) <span class="required">*</span></label>
              <input class="form-input mono" id="fUnitPrice" type="number" step="0.01" min="0"
                     value="${r ? (r.unitPrice||0) : ''}" placeholder="元/吨" oninput="recalc()">
            </div>
          </div>

          <!-- 实时计算结果 -->
          <div style="margin-top:20px;background:var(--slate-50);border-radius:var(--radius);padding:16px 20px;
                      display:flex;gap:32px;align-items:center;flex-wrap:wrap">
            <div>
              <div class="stat-label">净重 (kg)</div>
              <div style="font-family:var(--font-mono);font-size:24px;font-weight:700;color:var(--blue)" id="calcNet">0.0</div>
              <div style="font-size:11px;color:var(--slate-400);margin-top:2px">毛重 − 扣皮</div>
            </div>
            <div style="color:var(--slate-300);font-size:20px">×</div>
            <div>
              <div class="stat-label">单价 (元/吨)</div>
              <div style="font-family:var(--font-mono);font-size:20px;color:var(--slate-600)" id="calcPrice">0</div>
            </div>
            <div style="color:var(--slate-300);font-size:20px">=</div>
            <div>
              <div class="stat-label">总金额 (元)</div>
              <div style="font-family:var(--font-mono);font-size:28px;font-weight:700;color:var(--teal-dark)" id="calcAmount">0.00</div>
              <div style="font-size:11px;color:var(--slate-400);margin-top:2px">(净重 ÷ 1000) × 单价</div>
            </div>
          </div>
        </div>
      </div>

      <!-- 操作按钮 -->
      <div class="btn-group" style="justify-content:flex-end">
        <a class="btn btn-outline" href="#/movements">取消</a>
        <button class="btn btn-primary btn-lg" type="button" id="btnSave" onclick="window.submitForm()">
          <i class="fa-solid fa-check"></i> 保存记录
        </button>
      </div>
    </form>
  `;

  // 分段按钮初始化
  initSegmentButtons(r ? r.type : 'inbound', isEdit);

  // 初始计算
  recalc();
}

function initSegmentButtons(type, disabled) {
  const buttons = document.querySelectorAll('#segType .segment-btn');
  buttons.forEach(btn => {
    const bt = btn.dataset.type;
    btn.className = 'segment-btn';
    if (bt === type) {
      btn.classList.add(type === 'inbound' ? 'active-inbound' : 'active-outbound');
    }
    if (!disabled) {
      btn.addEventListener('click', () => {
        buttons.forEach(b => {
          b.className = 'segment-btn';
          b.classList.add(b.dataset.type === 'inbound' ? 'active-inbound' : 'active-outbound');
        });
      });
    }
  });
}

// 实时计算
window.recalc = function() {
  const gross = parseFloat(document.getElementById('fGrossWeight')?.value) || 0;
  const tare = parseFloat(document.getElementById('fTareWeight')?.value) || 0;
  const price = parseFloat(document.getElementById('fUnitPrice')?.value) || 0;
  const net = gross - tare;
  const amount = net > 0 ? (net / 1000) * price : 0;

  const netEl = document.getElementById('calcNet');
  const priceEl = document.getElementById('calcPrice');
  const amountEl = document.getElementById('calcAmount');
  if (netEl) netEl.textContent = net.toFixed(1);
  if (priceEl) priceEl.textContent = price.toFixed(2);
  if (amountEl) amountEl.textContent = amount.toFixed(2);
};

// 提交表单
window.submitForm = async function() {
  const warehouseId = document.getElementById('fWarehouseId').value;
  if (!warehouseId) return window.showToast('请选择仓库', 'warning');

  const partnerName = document.getElementById('fPartnerName').value.trim();
  if (!partnerName) return window.showToast('交易对象不能为空', 'warning');

  const gross = parseFloat(document.getElementById('fGrossWeight').value) || 0;
  const tare = parseFloat(document.getElementById('fTareWeight').value) || 0;
  const net = gross - tare;
  if (net <= 0) return window.showToast('净重必须大于 0（当前: ' + net.toFixed(1) + ' kg）', 'warning');

  const unitPrice = parseFloat(document.getElementById('fUnitPrice').value) || 0;
  if (unitPrice < 0) return window.showToast('单价不能为负数', 'warning');

  // 获取类型
  const activeBtn = document.querySelector('#segType .segment-btn.active-inbound, #segType .segment-btn.active-outbound');
  const type = activeBtn ? activeBtn.dataset.type : 'inbound';

  const body = {
    warehouseId,
    partnerName,
    type,
    grossWeight: gross,
    tareWeight: tare,
    quantity: net,
    unitPrice,
    color: document.getElementById('fColor').value.trim(),
    variety: document.getElementById('fVariety').value.trim(),
    deliveryPerson: document.getElementById('fDeliveryPerson').value.trim() || null,
    totalPieces: parseInt(document.getElementById('fTotalPieces').value) || null,
  };

  const btn = document.getElementById('btnSave');
  btn.disabled = true;
  btn.innerHTML = '<div class="spinner" style="width:16px;height:16px;border-width:2px"></div> 保存中...';

  try {
    if (editingId) {
      await api.put('/api/movements/' + editingId, body);
      window.showToast('记录已更新', 'success');
    } else {
      await api.post('/api/movements', body);
      window.showToast('记录已创建', 'success');
    }
    location.hash = '#/movements';
  } catch (e) {
    window.showToast(e.message, 'error');
    btn.disabled = false;
    btn.innerHTML = '<i class="fa-solid fa-check"></i> 保存记录';
  }
};
