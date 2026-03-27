-- EMPLOYEE TABLE
CREATE TABLE Employee (
    employee_id INT,
    department_id INT,
    salary DECIMAL(10,2),
    hire_date DATE
);

-- DEPARTMENT TABLE
CREATE TABLE Department (
    department_id INT,
    department_name VARCHAR(100)
);

-- CUSTOMERS
CREATE TABLE Customers (
    customer_id INT,
    customer_name VARCHAR(100)
);

-- ORDERS
CREATE TABLE Orders (
    order_id INT,
    customer_id INT,
    order_date DATE,
    total_amount DECIMAL(10,2),
    region VARCHAR(50)
);

-- SALES
CREATE TABLE Sales (
    product_id INT,
    quantity INT,
    price DECIMAL(10,2)
);

-- PRODUCTS
CREATE TABLE Products (
    product_id INT,
    product_name VARCHAR(100)
);

-- RETURNS
CREATE TABLE Returns (
    customer_id INT
);

-- ORDER DETAILS (for basket analysis)
CREATE TABLE Order_Details (
    order_id INT,
    product_id INT
);

-- USERS
CREATE TABLE Users (
    user_id INT,
    signup_date DATE
);

-- PURCHASES
CREATE TABLE Purchases (
    user_id INT,
    purchase_date DATE
);

-- LOGINS
CREATE TABLE Logins (
    user_id INT,
    login_date DATE
);

-- FUNNEL
CREATE TABLE Funnel (
    stage VARCHAR(50)
);