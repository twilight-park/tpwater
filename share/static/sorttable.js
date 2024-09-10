class SortableTable {
  constructor(tableId, config) {
    this.table = document.getElementById(tableId);
    this.config = config;
    this.data = [];
    this.sortColumn = null;
    this.sortDirection = 1;

    this.createHeader();
    this.createBody();
  }

  createHeader() {
    const thead = document.createElement('thead');
    const headerRow = document.createElement('tr');

    this.config.forEach(column => {
      const th = document.createElement('th');
      th.textContent = column.name;
      th.addEventListener('click', () => this.sortBy(column.key));
      headerRow.appendChild(th);
    });

    thead.appendChild(headerRow);
    this.table.appendChild(thead);
  }

  createBody() {
    this.tbody = document.createElement('tbody');
    this.table.appendChild(this.tbody);
  }

  setData(data) {
    this.data = data;
    this.render();
  }

  render() {
    this.tbody.innerHTML = '';
    this.data.forEach(row => {
      const tr = document.createElement('tr');
      this.config.forEach(column => {
        const td = document.createElement('td');
        let value;
        if (typeof column.key === 'function') {
          value = column.key(row);
        } else {
          value = row[column.key];
        }
        td.textContent = column.format ? column.format(value) : value;
        tr.appendChild(td);
      });
      this.tbody.appendChild(tr);
    });
  }

  sortBy(columnKey) {
    if (this.sortColumn === columnKey) {
      this.sortDirection *= -1;
    } else {
      this.sortColumn = columnKey;
      this.sortDirection = 1;
    }

    this.data.sort((a, b) => {
      let aValue = typeof columnKey === 'function' ? columnKey(a) : a[columnKey];
      let bValue = typeof columnKey === 'function' ? columnKey(b) : b[columnKey];

      if (aValue < bValue) return -1 * this.sortDirection;
      if (aValue > bValue) return 1 * this.sortDirection;
      return 0;
    });

    this.render();
  }
}
