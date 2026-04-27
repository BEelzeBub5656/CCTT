// ── 仓库管理 ──
import { api } from '../api.js';

export async function renderWarehouses() {
  const main = document.getElementById('mainContent');
  main.innerHTML = '<div class="page-loader"><div class="spinner"></div></div>';

  await refresh();

  document.querySelectorAll('.nav-link').forEach(a => {
    a.classList.toggle('active', a.getAttribute('data-route') === 'warehouses');
  });
}

async function refresh() {
  const main = document.getElementById('mainContent');
  try {
    const warehouses = await api.get('/api/warehouses');

    // 获取每个仓库的记录数
    const stats = await api.get('/api/stats');

    main.innerHTML = `
      <div class="page-title">
        <i class="fa-solid fa-warehouse" style="color:var(--teal)"></i>
        仓库管理
        <span class="sub">${warehouses.length} 个仓库</span>
      </div>

      <div style="margin-bottom:20px">
        <button class="btn btn-primary" onclick="window.showAddWarehouseModal()">
          <i class="fa-solid fa-plus"></i> 添加仓库
        </button>
      </div>

      ${warehouses.length ? `
        <div class="warehouse-list">
          ${warehouses.map(w => `
            <div class="warehouse-card">
              <div>
                <div class="wh-name">
                  <i class="fa-solid fa-warehouse" style="color:var(--teal);margin-right:6px"></i>
                  ${escHtml(w.name)}
                </div>
                <div class="wh-count">
                  ID: ${w.id.substring(0, 8)}...
                </div>
              </div>
              <div class="btn-group">
                <button class="btn btn-sm btn-outline" onclick="window.editWarehouse('${w.id}', '${escHtml(w.name)}')">
                  <i class="fa-solid fa-pen"></i>
                </button>
                <button class="btn btn-sm btn-danger" onclick="window.deleteWarehouse('${w.id}', '${escHtml(w.name)}')">
                  <i class="fa-solid fa-trash"></i>
                </button>
              </div>
            </div>
          `).join('')}
        </div>
      ` : '<div class="empty-state"><i class="fa-solid fa-warehouse"></i><p>还没有仓库，请先添加</p></div>'}
    `;
  } catch (e) {
    main.innerHTML = '<div class="empty-state"><i class="fa-solid fa-triangle-exclamation"></i><p>加载失败: ' + escHtml(e.message) + '</p></div>';
  }
}

function escHtml(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

// ── 全局函数（供 onclick 调用）──

window.showAddWarehouseModal = function() {
  window.showModal(`
    <div class="modal-header">添加仓库</div>
    <div class="modal-body">
      <div class="form-group">
        <label class="form-label">仓库名称 <span class="required">*</span></label>
        <input class="form-input" id="whNameInput" placeholder="输入仓库名称" autofocus>
      </div>
    </div>
    <div class="modal-footer">
      <button class="btn btn-outline" onclick="closeModal()">取消</button>
      <button class="btn btn-primary" onclick="window.submitAddWarehouse()">创建</button>
    </div>
  `);
};

window.submitAddWarehouse = async function() {
  const name = document.getElementById('whNameInput').value.trim();
  if (!name) return window.showToast('请输入仓库名称', 'warning');
  try {
    await api.post('/api/warehouses', { name });
    window.showToast('仓库已创建', 'success');
    closeModal();
    refresh();
  } catch (e) {
    window.showToast(e.message, 'error');
  }
};

window.editWarehouse = function(id, name) {
  window.showModal(`
    <div class="modal-header">编辑仓库</div>
    <div class="modal-body">
      <div class="form-group">
        <label class="form-label">仓库名称 <span class="required">*</span></label>
        <input class="form-input" id="whNameInput" value="${escHtml(name)}" autofocus>
      </div>
    </div>
    <div class="modal-footer">
      <button class="btn btn-outline" onclick="closeModal()">取消</button>
      <button class="btn btn-primary" onclick="window.submitEditWarehouse('${id}')">保存</button>
    </div>
  `);
};

window.submitEditWarehouse = async function(id) {
  const name = document.getElementById('whNameInput').value.trim();
  if (!name) return window.showToast('请输入仓库名称', 'warning');
  try {
    await api.put('/api/warehouses/' + id, { name });
    window.showToast('仓库已更新', 'success');
    closeModal();
    refresh();
  } catch (e) {
    window.showToast(e.message, 'error');
  }
};

window.deleteWarehouse = async function(id, name) {
  // 先检查是否有关联记录
  try {
    const movements = await api.get('/api/movements', { warehouseId: id, limit: 1 });
    if (movements.pagination.total > 0) {
      return window.showToast('该仓库下有 ' + movements.pagination.total + ' 条出入库记录，无法删除', 'error');
    }
  } catch (e) { /* 忽略检查错误，继续删除尝试 */ }

  window.showModal(`
    <div class="modal-header">确认删除</div>
    <div class="modal-body">
      <p>确定要删除仓库 "<strong>${escHtml(name)}</strong>" 吗？</p>
      <p style="color:var(--slate-500);font-size:14px">此操作不可撤销</p>
    </div>
    <div class="modal-footer">
      <button class="btn btn-outline" onclick="closeModal()">取消</button>
      <button class="btn btn-danger" onclick="window.submitDeleteWarehouse('${id}')">确认删除</button>
    </div>
  `);
};

window.submitDeleteWarehouse = async function(id) {
  try {
    await api.del('/api/warehouses/' + id);
    window.showToast('仓库已删除', 'success');
    closeModal();
    refresh();
  } catch (e) {
    window.showToast(e.message, 'error');
  }
};
