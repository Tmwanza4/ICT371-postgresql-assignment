-- Scenario 1: University Library Book Loans

DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;
DROP PROCEDURE IF EXISTS borrow_book(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS return_book(INT);

-- 1. Tables and sample data
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(10) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED', 'RETURNED'))
);

INSERT INTO books (title, available_copies) VALUES
    ('Database Systems', 10),
    ('Java Programming', 3),
    ('Computer Networks', 0);

SELECT * FROM books ORDER BY book_id;

-- 2. IF / ELSIF / ELSE: stock status of each book
DO $$
DECLARE
    rec    RECORD;
    status TEXT;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            status := 'UNAVAILABLE';
        ELSIF rec.available_copies <= 3 THEN
            status := 'LOW on copies';
        ELSE
            status := 'sufficiently stocked';
        END IF;
        RAISE NOTICE '% (% copies): %', rec.title, rec.available_copies, status;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', n;
        n := n + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', i;
    END LOOP;
END $$;

-- 4. borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id INT, p_student_number VARCHAR, p_quantity INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_quantity;
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Loan REJECTED for student %: requested %, only % available',
            p_student_number, p_quantity, v_available;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student_number, p_quantity, 'BORROWED');

    RAISE NOTICE 'Loan recorded for student %: % copy(ies) of book %',
        p_student_number, p_quantity, p_book_id;
END $$;

-- 5. Two valid loans and one exceeding the available copies
CALL borrow_book(1, '2023001', 2);   -- valid
CALL borrow_book(2, '2023002', 1);   -- valid
CALL borrow_book(2, '2023003', 5);   -- exceeds available copies (rejected)

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 6. return_book procedure
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id  INT;
    v_quantity INT;
    v_status   VARCHAR;
BEGIN
    SELECT book_id, quantity, loan_status
    INTO v_book_id, v_quantity, v_status
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned; no copies restored', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_quantity
    WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned; % copy(ies) restored', p_loan_id, v_quantity;
END $$;

CALL return_book(1);   -- restores copies
CALL return_book(1);   -- second call must not restore again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 7. Explicit cursor: books with few copies remaining (3 or fewer)
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT title, available_copies FROM books
        WHERE available_copies <= 3 ORDER BY available_copies;
    v_title  books.title%TYPE;
    v_copies books.available_copies%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low stock: % - % copy(ies) left', v_title, v_copies;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. Borrow zero copies: handled with an EXCEPTION block
DO $$
BEGIN
    CALL borrow_book(1, '2023004', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;