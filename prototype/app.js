const root = document.documentElement;
const themeToggle = document.querySelector('.theme-toggle');
const viewButtons = document.querySelectorAll('.view-button');
const checkButtons = document.querySelectorAll('.check-button');
const completedToggle = document.querySelector('.completed-toggle');
const completedList = document.querySelector('.completed-list');
const quickAdd = document.querySelector('.quick-add');
const taskList = document.querySelector('.task-list');
const toast = document.querySelector('.toast');
let toastTimer;

const savedTheme = localStorage.getItem('todo-prototype-theme');
if (savedTheme) root.dataset.theme = savedTheme;

themeToggle.addEventListener('click', () => {
  const nextTheme = root.dataset.theme === 'dark' ? 'light' : 'dark';
  root.dataset.theme = nextTheme;
  localStorage.setItem('todo-prototype-theme', nextTheme);
});

viewButtons.forEach((button) => {
  button.addEventListener('click', () => {
    const isTimeline = button.dataset.view === 'timeline';
    viewButtons.forEach((item) => item.classList.toggle('active', item === button));
    document.querySelector('.events-nav').classList.toggle('hidden', isTimeline);
    document.querySelector('.timeline-nav').classList.toggle('hidden', !isTimeline);
    document.querySelector('.events-content').classList.toggle('hidden', isTimeline);
    document.querySelector('.timeline-content').classList.toggle('hidden', !isTimeline);
  });
});

document.querySelectorAll('.tree-row, .time-group').forEach((row) => {
  row.addEventListener('click', () => {
    row.parentElement.querySelectorAll(':scope > .active').forEach((item) => item.classList.remove('active'));
    row.classList.add('active');
  });
});

function showToast(message = '任务已完成') {
  toast.firstChild.textContent = `${message} `;
  toast.classList.add('show');
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast.classList.remove('show'), 2600);
}

checkButtons.forEach((button) => {
  button.addEventListener('click', () => {
    const card = button.closest('.task-card');
    const isChecked = button.classList.toggle('checked');
    card.classList.toggle('completed', isChecked);
    if (isChecked && !button.querySelector('svg')) {
      button.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"></path></svg>';
    }
    if (!isChecked) button.innerHTML = '';
    showToast(isChecked ? '任务已完成' : '已恢复任务');
  });
});

completedToggle.addEventListener('click', () => {
  const expanded = completedToggle.getAttribute('aria-expanded') === 'true';
  completedToggle.setAttribute('aria-expanded', String(!expanded));
  completedList.classList.toggle('hidden', expanded);
});

quickAdd.addEventListener('submit', (event) => {
  event.preventDefault();
  const input = quickAdd.querySelector('input');
  const title = input.value.trim();
  if (!title) return;

  const card = document.createElement('article');
  card.className = 'task-card';
  card.innerHTML = `
    <button class="check-button" type="button"></button>
    <div class="task-main"><div class="task-title"></div><div class="task-meta"><span>刚刚创建</span></div></div>
    <button class="drag-handle" type="button" aria-label="拖动排序"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="9" cy="7" r="1"></circle><circle cx="15" cy="7" r="1"></circle><circle cx="9" cy="12" r="1"></circle><circle cx="15" cy="12" r="1"></circle><circle cx="9" cy="17" r="1"></circle><circle cx="15" cy="17" r="1"></circle></svg></button>`;
  card.querySelector('.task-title').textContent = title;
  const newCheckButton = card.querySelector('.check-button');
  newCheckButton.setAttribute('aria-label', `完成：${title}`);
  newCheckButton.addEventListener('click', (clickEvent) => {
    const button = clickEvent.currentTarget;
    button.classList.add('checked');
    button.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"></path></svg>';
    card.classList.add('completed');
    showToast();
  });
  taskList.append(card);
  input.value = '';
  showToast('已添加子任务');
});

toast.querySelector('button').addEventListener('click', () => toast.classList.remove('show'));
