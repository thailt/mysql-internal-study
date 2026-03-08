CREATE TABLE IF NOT EXISTS employees (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    department VARCHAR(50),
    salary DECIMAL(10,2),
    hire_date DATE,
    INDEX idx_department (department),
    INDEX idx_salary (salary),
    INDEX idx_hire_date (hire_date)
) ENGINE=InnoDB;

INSERT INTO employees (first_name, last_name, email, department, salary, hire_date) VALUES
('Alice', 'Nguyen', 'alice@lab.com', 'Engineering', 95000, '2020-01-15'),
('Bob', 'Tran', 'bob@lab.com', 'Engineering', 88000, '2021-03-22'),
('Charlie', 'Le', 'charlie@lab.com', 'Marketing', 72000, '2019-06-10'),
('Diana', 'Pham', 'diana@lab.com', 'Sales', 68000, '2022-08-01'),
('Eve', 'Vo', 'eve@lab.com', 'Engineering', 102000, '2018-11-30');

CREATE TABLE IF NOT EXISTS orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id BIGINT NOT NULL,
    product VARCHAR(100),
    amount DECIMAL(10,2),
    order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    status ENUM('pending', 'processing', 'completed', 'cancelled') DEFAULT 'pending',
    INDEX idx_employee (employee_id),
    INDEX idx_status (status),
    INDEX idx_order_date (order_date),
    FOREIGN KEY (employee_id) REFERENCES employees(id)
) ENGINE=InnoDB;
