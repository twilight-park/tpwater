class SortableTable {
  constructor(tableId, config) {
    this.table = document.getElementById(tableId);
    this.config = config;
    this.data = [];
    this.sortColumns = [];
    this.sortDirections = {};

    this.createHeader();
    this.createBody();
  }

  createHeader() {
    const thead = document.createElement('thead');
    const headerRow = document.createElement('tr');

    this.config.forEach(column => {
      const th = document.createElement('th');
      th.textContent = column.name;
      th.addEventListener('click', (event) => this.handleHeaderClick(event, column.key));
      th.style.cursor = 'pointer';
      this.sortDirections[column.key] = 0; // 0 for unsorted, 1 for ascending, -1 for descending
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
    this.sortData();
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
    this.updateSortIndicators();
  }

  handleHeaderClick(event, columnKey) {
    const isShiftPressed = event.shiftKey;
    
    if (!isShiftPressed) {
      // Single column sort
      this.sortColumns = [columnKey];
      this.sortDirections = { [columnKey]: this.sortDirections[columnKey] === 1 ? -1 : 1 };
    } else {
      // Multi-column sort
      const columnIndex = this.sortColumns.indexOf(columnKey);
      if (columnIndex === -1) {
        // Add new column to sort
        this.sortColumns.push(columnKey);
        this.sortDirections[columnKey] = 1;
      } else {
        // Toggle sort direction or remove if already descending
        if (this.sortDirections[columnKey] === 1) {
          this.sortDirections[columnKey] = -1;
        } else {
          this.sortColumns.splice(columnIndex, 1);
          delete this.sortDirections[columnKey];
        }
      }
    }

    this.sortData();
    this.render();
  }

  sortData(otherData = null, otherSortColumns = null, otherSortDirections) {
    const data = otherData ?? this.data;
    const sortColumns = otherSortColumns ?? this.sortColumns;
    const sortDirections = otherSortDirections ?? this.sortDirections;

    data.sort((a, b) => {
      for (const columnKey of sortColumns) {
        const direction = sortDirections[columnKey];
        let aValue = typeof columnKey === 'function' ? columnKey(a) : a[columnKey];
        let bValue = typeof columnKey === 'function' ? columnKey(b) : b[columnKey];

        if (aValue < bValue) return -1 * direction;
        if (aValue > bValue) return 1 * direction;
      }
      return 0;
    });

    return data;
  }

  updateSortIndicators() {
    const headers = this.table.querySelectorAll('th');
    headers.forEach((header, index) => {
      const columnKey = this.config[index].key;
      const sortIndex = this.sortColumns.indexOf(columnKey);
      const direction = this.sortDirections[columnKey];

      // Remove existing indicators
      header.textContent = this.config[index].name;

      if (sortIndex !== -1) {
        const indicator = direction === 1 ? ' ▲' : ' ▼';
        header.textContent += `${indicator}${sortIndex > 0 ? sortIndex + 1 : ''}`;
      }
    });
  }

  setInitialSort(sortColumns) {
    this.sortColumns = [];
    this.sortDirections = {};

    sortColumns.forEach(({ key, direction }) => {
      this.sortColumns.push(key);
      this.sortDirections[key] = direction === 'asc' ? 1 : -1;
    });

    if (this.data.length > 0) {
      this.sortData();
      this.render();
    }
  }
}
