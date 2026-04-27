// ── 记录详情（凭证样式） ──
import { api } from '../api.js';
import { typeBadge, syncBadge, esc } from './dashboard.js';
import { formatDate } from './movements.js';

export async function renderMovementDetail(id) {
  const main = document.getElementById('mainContent');
  main.innerHTML = '<div class="page-loader"><div class="spinner"></div></div>';

  document.querySelectorAll('.nav-link').forEach(a => {
    a.classList.toggle('active', a.getAttribute('data-route') === 'movements');
  });

  try {
    const r = await api.get('/api/movements/' + id);

    // 毛重-扣皮 校验
    const netFromGross = r.grossWeight - r.tareWeight;
    const diff = Math.abs(netFromGross - r.quantity);
    const isNetMatch = diff < 0.01;

    main.innerHTML = `
      <div class="page-title">
        <i class="fa-solid fa-file-invoice" style="color:var(--teal)"></i>
        单据详情
        <span class="sub">${esc(r.partnerName)}</span>
      </div>

      <div class="voucher-card">
        <!-- 头部：类型 + 金额 -->
        <div class="voucher-header">
          <div>
            ${typeBadge(r.type)}
            ${r.isDeleted ? ' <span class="badge badge-deleted">已作废</span>' : ''}
          </div>
          <div style="text-align:right">
            <div class="amount-label">总金额</div>
            <div class="amount-large">¥ ${r.totalAmount.toFixed(2)}</div>
          </div>
        </div>

        <!-- 基本信息 -->
        <div class="voucher-section">
          <div class="voucher-section-title">基本信息</div>
          <div class="voucher-row">
            <span class="voucher-label">流水号</span>
            <span class="voucher-value" style="font-family:var(--font-mono);font-size:12px">${r.id}</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">交易时间</span>
            <span class="voucher-value">${formatDate(r.timestamp)}</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">仓库</span>
            <span class="voucher-value">${esc(r.warehouseName||'-')}</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">单据类型</span>
            <span class="voucher-value">${r.type === 'inbound' ? '入库' : '出库'}</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">同步状态</span>
            <span class="voucher-value">${syncBadge(r.syncStatus)}</span>
          </div>
        </div>

        <!-- 交易信息 -->
        <div class="voucher-section">
          <div class="voucher-section-title">交易信息</div>
          <div class="voucher-row">
            <span class="voucher-label">交易对象</span>
            <span class="voucher-value">${esc(r.partnerName)}</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">颜色</span>
            <span class="voucher-value">${esc(r.color||'—')}</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">品种</span>
            <span class="voucher-value">${esc(r.variety||'—')}</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">送货人</span>
            <span class="voucher-value">${esc(r.deliveryPerson||'—')}</span>
          </div>
        </div>

        <!-- 重量明细 -->
        <div class="voucher-section">
          <div class="voucher-section-title">重量明细</div>
          <div class="voucher-row">
            <span class="voucher-label">总件数</span>
            <span class="voucher-value">${r.totalPieces != null ? r.totalPieces + ' 件' : '—'}</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">毛重</span>
            <span class="voucher-value" style="font-family:var(--font-mono)">${(r.grossWeight||0).toFixed(1)} kg</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">扣皮</span>
            <span class="voucher-value" style="font-family:var(--font-mono)">${(r.tareWeight||0).toFixed(1)} kg</span>
          </div>
          <div class="voucher-row highlight">
            <span class="voucher-label">净重</span>
            <span class="voucher-value">${r.quantity.toFixed(1)} kg</span>
          </div>
          ${r.grossWeight > 0 ? `
            <div class="voucher-row" style="margin-top:4px">
              <span class="voucher-label" style="font-size:12px">校验: 毛重 − 扣皮 = ${netFromGross.toFixed(1)} kg</span>
              <span class="voucher-verify ${isNetMatch ? 'match' : 'mismatch'}">${isNetMatch ? '✓ 一致' : '⚠ 偏差 ' + diff.toFixed(1) + ' kg'}</span>
            </div>
          ` : ''}
        </div>

        <!-- 金额明细 -->
        <div class="voucher-section">
          <div class="voucher-section-title">金额明细</div>
          <div class="voucher-row">
            <span class="voucher-label">单价</span>
            <span class="voucher-value" style="font-family:var(--font-mono)">${r.unitPrice.toFixed(2)} 元/吨</span>
          </div>
          <div class="voucher-row">
            <span class="voucher-label">计算公式</span>
            <span class="voucher-value" style="font-size:13px">(${r.quantity.toFixed(1)} kg ÷ 1000) × ${r.unitPrice.toFixed(2)} 元/吨</span>
          </div>
          <div class="voucher-row highlight">
            <span class="voucher-label">总金额</span>
            <span class="voucher-value">¥ ${r.totalAmount.toFixed(2)}</span>
          </div>
        </div>
      </div>

      <!-- 操作按钮 -->
      <div class="btn-group" style="justify-content:center;margin-top:20px">
        <a class="btn btn-outline" href="#/movements"><i class="fa-solid fa-arrow-left"></i> 返回列表</a>
        ${r.isDeleted ? `
          <button class="btn btn-outline" onclick="window.restoreFromDetail('${r.id}')"><i class="fa-solid fa-rotate-left"></i> 恢复记录</button>
        ` : `
          <a class="btn btn-outline" href="#/movements/${r.id}/edit"><i class="fa-solid fa-pen"></i> 编辑</a>
          <button class="btn btn-danger" onclick="window.voidFromDetail('${r.id}','${esc(r.partnerName)}')"><i class="fa-solid fa-ban"></i> 作废</button>
        `}
      </div>
    `;
  } catch (e) {
    main.innerHTML = '<div class="empty-state"><i class="fa-solid fa-triangle-exclamation"></i><p>加载失败: ' + esc(e.message) + '</p></div>';
  }
}

// ── 全局函数 ──
window.voidFromDetail = function(id, name) {
  window.showModal(`
    <div class="modal-header">确认作废</div>
    <div class="modal-body">
      <p>确定要作废记录 "<strong>${name}</strong>" 吗？</p>
      <p style="color:var(--red);font-size:14px">此操作不可撤销</p>
    </div>
    <div class="modal-footer">
      <button class="btn btn-outline" onclick="closeModal()">取消</button>
      <button class="btn btn-danger" onclick="window.submitVoidDetail('${id}')">确认作废</button>
    </div>
  `);
};

window.submitVoidDetail = async function(id) {
  try {
    await api.del('/api/movements/' + id);
    window.showToast('记录已作废', 'success');
    closeModal();
    location.hash = '#/movements/' + id;
    renderMovementDetail(id);
  } catch (e) {
    window.showToast(e.message, 'error');
  }
};

window.restoreFromDetail = async function(id) {
  try {
    await api.post('/api/movements/' + id + '/restore');
    window.showToast('记录已恢复', 'success');
    location.hash = '#/movements/' + id;
    renderMovementDetail(id);
  } catch (e) {
    window.showToast(e.message, 'error');
  }
};
