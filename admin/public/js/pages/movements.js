// ── 出入库记录列表 ──
import { api } from '../api.js';
import { store } from '../state.js';
import { typeBadge, syncBadge, esc } from './dashboard.js';

export function formatDate(ts) {
  const d = new Date(ts);
  const pad = n => String(n).padStart(2, '0');
  return d.getFullYear() + '-' + pad(d.getMonth()+1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}

let currentFilter = { page: 1, limit: 50 };

export async function renderMovements(params = {}) {
  const main = document.getElementById('mainContent');
  main.innerHTML = '<div class="page-loader"><div class="spinner"></div></div>';

  document.querySelectorAll('.nav-link').forEach(a => {
    a.classList.toggle('active', a.getAttribute('data-route') === 'movements');
  });

  const warehouses = await store.loadWarehouses();

  main.innerHTML = `
    <div class="page-title">
      <i class="fa-solid fa-arrow-right-arrow-left" style="color:var(--teal)"></i>
      出入库记录
      <span class="sub" id="totalLabel"></span>
    </div>

    <div style="margin-bottom:16px;display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px">
      <div class="filter-bar">
        <select class="form-select" id="fWh" onchange="window.applyFilter()">
          <option value="">所有仓库</option>
          ${warehouses.map(w => `<option value="${w.id}">${esc(w.name)}</option>`).join('')}
        </select>
        <select class="form-select" id="fType" onchange="window.applyFilter()">
          <option value="">全部类型</option>
          <option value="inbound">入库</option>
          <option value="outbound">出库</option>
        </select>
        <select class="form-select" id="fSync" onchange="window.applyFilter()">
          <option value="">全部同步状态</option>
          <option value="pending">未同步</option>
          <option value="synced">已同步</option>
          <option value="syncing">正在同步</option>
          <option value="failed">同步失败</option>
        </select>
        <input class="form-input search-input" id="fSearch" placeholder="搜索交易对象/颜色/品种..." onkeydown="if(event.key==='Enter')window.applyFilter()">
        <label style="font-size:13px;display:flex;align-items:center;gap:4px;color:var(--slate-500)">
          <input type="checkbox" id="fDeleted" onchange="window.applyFilter()"> 含已作废
        </label>
      </div>
      <a class="btn btn-primary" href="#/movements/new">
        <i class="fa-solid fa-plus"></i> 新增记录
      </a>
    </div>

    <div class="card">
      <div class="table-wrap">
        <div id="movementsTable"><div class="page-loader" style="padding:40px"><div class="spinner"></div></div></div>
      </div>
      <div id="movementsPagination"></div>
    </div>
  `;

  await loadData();
}

async function loadData() {
  const params = {
    warehouseId: document.getElementById('fWh')?.value || '',
    type: document.getElementById('fType')?.value || '',
    syncStatus: document.getElementById('fSync')?.value || '',
    search: document.getElementById('fSearch')?.value || '',
    includeDeleted: document.getElementById('fDeleted')?.checked || false,
    page: currentFilter.page,
    limit: currentFilter.limit,
  };

  try {
    const result = await api.get('/api/movements', params);
    document.getElementById('totalLabel').textContent = '共 ' + result.pagination.total + ' 条';
    renderTable(result.data);
    renderPagination(result.pagination, params);
  } catch (e) {
    document.getElementById('movementsTable').innerHTML = '<div class="empty-state"><p>加载失败: ' + esc(e.message) + '</p></div>';
  }
}

function renderTable(rows) {
  if (!rows.length) {
    document.getElementById('movementsTable').innerHTML = '<div class="empty-state"><i class="fa-solid fa-inbox"></i><p>暂无记录</p></div>';
    document.getElementById('movementsPagination').innerHTML = '';
    return;
  }

  document.getElementById('movementsTable').innerHTML = `
    <table>
      <thead>
        <tr>
          <th>时间</th><th>类型</th><th>交易对象</th><th>颜色/品种</th>
          <th>仓库</th><th>净重(kg)</th><th>单价(元/吨)</th><th>总金额</th>
          <th>同步</th><th>操作</th>
        </tr>
      </thead>
      <tbody>
        ${rows.map(r => {
          const cls = r.isDeleted ? 'deleted' : '';
          return `
            <tr class="${cls}">
              <td style="font-size:13px;white-space:nowrap">${formatDate(r.timestamp)}</td>
              <td>${r.isDeleted ? '<span class="badge badge-deleted">已作废</span>' : typeBadge(r.type)}</td>
              <td><strong>${esc(r.partnerName)}</strong>${r.deliveryPerson ? '<br><span style="font-size:12px;color:var(--slate-500)">送货: ' + esc(r.deliveryPerson) + '</span>' : ''}</td>
              <td>${esc(r.color||'-')} / ${esc(r.variety||'-')}</td>
              <td>${esc(r.warehouseName||'-')}</td>
              <td style="font-family:var(--font-mono)">${(r.quantity||0).toFixed(1)}</td>
              <td style="font-family:var(--font-mono)">${(r.unitPrice||0).toFixed(2)}</td>
              <td style="font-family:var(--font-mono);font-weight:600;color:var(--teal-dark)">${(r.totalAmount||0).toFixed(2)}</td>
              <td>${syncBadge(r.syncStatus)}</td>
              <td class="actions-cell">
                <a class="btn btn-sm btn-outline" href="#/movements/${r.id}" title="详情"><i class="fa-solid fa-eye"></i></a>
                ${r.isDeleted ? `
                  <button class="btn btn-sm btn-outline" onclick="window.restoreMovement('${r.id}')" title="恢复"><i class="fa-solid fa-rotate-left"></i></button>
                ` : `
                  <a class="btn btn-sm btn-outline" href="#/movements/${r.id}/edit" title="编辑"><i class="fa-solid fa-pen"></i></a>
                  <button class="btn btn-sm btn-danger" onclick="window.voidMovement('${r.id}','${esc(r.partnerName)}')" title="作废"><i class="fa-solid fa-ban"></i></button>
                `}
              </td>
            </tr>
          `;
        }).join('')}
      </tbody>
    </table>
  `;
}

function renderPagination(p, params) {
  if (p.totalPages <= 1) {
    document.getElementById('movementsPagination').innerHTML = '';
    return;
  }
  let html = '<div class="pagination">';
  html += `<button ${p.page <= 1 ? 'disabled' : ''} onclick="window.goPage(${p.page - 1})">上一页</button>`;
  html += `<span class="page-info">第 ${p.page} / ${p.totalPages} 页（共 ${p.total} 条）</span>`;
  html += `<button ${p.page >= p.totalPages ? 'disabled' : ''} onclick="window.goPage(${p.page + 1})">下一页</button>`;
  html += '</div>';
  document.getElementById('movementsPagination').innerHTML = html;
}

// ── 全局函数 ──

window.applyFilter = function() {
  currentFilter.page = 1;
  loadData();
};

window.goPage = function(page) {
  currentFilter.page = page;
  loadData();
};

window.voidMovement = function(id, name) {
  window.showModal(`
    <div class="modal-header">确认作废</div>
    <div class="modal-body">
      <p>确定要作废记录 "<strong>${name}</strong>" 吗？</p>
      <p style="color:var(--red);font-size:14px">作废后记录保留但标记为无效，此操作不可撤销</p>
    </div>
    <div class="modal-footer">
      <button class="btn btn-outline" onclick="closeModal()">取消</button>
      <button class="btn btn-danger" onclick="window.submitVoid('${id}')">确认作废</button>
    </div>
  `);
};

window.submitVoid = async function(id) {
  try {
    await api.del('/api/movements/' + id);
    window.showToast('记录已作废', 'success');
    closeModal();
    loadData();
  } catch (e) {
    window.showToast(e.message, 'error');
  }
};

window.restoreMovement = async function(id) {
  try {
    await api.post('/api/movements/' + id + '/restore');
    window.showToast('记录已恢复', 'success');
    loadData();
  } catch (e) {
    window.showToast(e.message, 'error');
  }
};
