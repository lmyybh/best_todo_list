const toast = document.querySelector('.toast');
const viewButtons = document.querySelectorAll('.view-button');
let toastTimer;

viewButtons.forEach((button) => {
  button.addEventListener('click', () => {
    const timeline = button.dataset.view === 'timeline';
    viewButtons.forEach((item) => item.classList.toggle('active', item === button));
    document.querySelector('.events-panel').classList.toggle('hidden', timeline);
    document.querySelector('.timeline-panel').classList.toggle('hidden', !timeline);
  });
});

if (location.hash === '#timeline') {
  document.querySelector('[data-view="timeline"]').click();
}

document.querySelectorAll('.date-option').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.date-option').forEach((item) => {
      const selected = item === button;
      item.classList.toggle('active', selected);
      item.setAttribute('aria-selected', String(selected));
    });
    document.querySelector('.timeline-view-options > span').textContent = button.dataset.dateTitle;
  });
});

document.querySelector('.today-button').addEventListener('click', () => {
  document.querySelector('.date-option').click();
});

document.querySelectorAll('.timeline-check').forEach((button) => {
  button.addEventListener('click', () => {
    const task = button.closest('.timeline-task');
    const done = task.classList.toggle('completed');
    button.classList.toggle('checked', done);
    button.innerHTML = done
      ? '<svg viewBox="0 0 24 24"><path d="m5 12 4 4L19 6"></path></svg>'
      : '';
    showToast(done ? '任务已完成' : '已恢复任务');
  });
});

document.querySelector('.completed-filter input').addEventListener('change', (event) => {
  document.querySelector('.completed-time-group').classList.toggle('hidden', !event.currentTarget.checked);
});

function showToast(message) {
  toast.textContent = message;
  toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('show'), 1800);
}

document.querySelectorAll('.disclosure').forEach((button) => {
  button.addEventListener('click', () => {
    const node = button.closest('.node');
    const children = node.nextElementSibling;
    if (!children?.classList.contains('children')) return;
    const expanded = button.getAttribute('aria-expanded') === 'true';
    button.setAttribute('aria-expanded', String(!expanded));
    children.hidden = expanded;
    button.querySelector('path').setAttribute('d', expanded ? 'm9 18 6-6-6-6' : 'm7 10 5 5 5-5');
  });
});

document.querySelectorAll('.node-main').forEach((button) => {
  button.addEventListener('click', (event) => {
    const status = event.target.closest('.status');
    const node = button.closest('.node');
    if (status && !status.classList.contains('branch-status')) {
      const done = node.classList.toggle('completed');
      status.classList.toggle('checked', done);
      status.innerHTML = done ? '<svg viewBox="0 0 24 24"><path d="m5 12 4 4L19 6"></path></svg>' : '';
      showToast(done ? '任务已完成' : '已恢复任务');
      return;
    }
    document.querySelectorAll('.node.selected').forEach((item) => item.classList.remove('selected'));
    node.classList.add('selected');
  });
});

document.querySelectorAll('.quick-add').forEach((form) => {
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const input = form.querySelector('input');
    const value = input.value.trim();
    if (!value) return;
    const node = document.createElement('div');
    node.className = 'node leaf';
    node.innerHTML = `<span class="disclosure-space"></span><button class="node-main" type="button"><span class="status"></span><span class="node-title"></span><time>刚刚</time></button><div class="node-actions"><button type="button">···</button></div>`;
    node.querySelector('.node-title').textContent = value;
    form.previousElementSibling.append(node);
    input.value = '';
    showToast('已添加任务');
  });
});
