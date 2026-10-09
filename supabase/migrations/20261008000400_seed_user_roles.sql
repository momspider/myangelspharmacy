INSERT INTO public."UserRole" (role_name, description)
VALUES
    ('customer', 'Pharmacy customer'),
    ('pharmacist', 'Pharmacy staff member'),
    ('admin', 'Pharmacy administrator')
ON CONFLICT (role_name) DO NOTHING;
