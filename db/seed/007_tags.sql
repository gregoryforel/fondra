-- Seed tags and assign them to demo recipes

-- Cuisine tags
INSERT INTO tags (name, category) VALUES
    ('French', 'cuisine'),
    ('British', 'cuisine'),
    ('American', 'cuisine'),
    ('Italian', 'cuisine'),
    ('Mediterranean', 'cuisine');

-- Meal type tags
INSERT INTO tags (name, category) VALUES
    ('Dinner', 'meal_type'),
    ('Lunch', 'meal_type'),
    ('Brunch', 'meal_type');

-- Course tags
INSERT INTO tags (name, category) VALUES
    ('Main Course', 'course'),
    ('Side Dish', 'course'),
    ('Appetizer', 'course'),
    ('Dessert', 'course');

-- Difficulty tags
INSERT INTO tags (name, category) VALUES
    ('Easy', 'difficulty'),
    ('Intermediate', 'difficulty'),
    ('Advanced', 'difficulty');

-- Technique tags
INSERT INTO tags (name, category) VALUES
    ('Roasting', 'technique'),
    ('Baking', 'technique'),
    ('Lamination', 'technique');

-- Season tags
INSERT INTO tags (name, category) VALUES
    ('Fall', 'season'),
    ('Winter', 'season'),
    ('Year-Round', 'season');

-- Assign tags to Classic Puff Pastry
INSERT INTO recipe_tags (recipe_id, tag_id) VALUES
    ((SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'), (SELECT id FROM tags WHERE name = 'French' AND category = 'cuisine')),
    ((SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'), (SELECT id FROM tags WHERE name = 'Advanced' AND category = 'difficulty')),
    ((SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'), (SELECT id FROM tags WHERE name = 'Baking' AND category = 'technique')),
    ((SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'), (SELECT id FROM tags WHERE name = 'Lamination' AND category = 'technique')),
    ((SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'), (SELECT id FROM tags WHERE name = 'Year-Round' AND category = 'season'));

-- Assign tags to Beef Wellington
INSERT INTO recipe_tags (recipe_id, tag_id) VALUES
    ((SELECT id FROM recipes WHERE slug = 'beef-wellington'), (SELECT id FROM tags WHERE name = 'British' AND category = 'cuisine')),
    ((SELECT id FROM recipes WHERE slug = 'beef-wellington'), (SELECT id FROM tags WHERE name = 'Dinner' AND category = 'meal_type')),
    ((SELECT id FROM recipes WHERE slug = 'beef-wellington'), (SELECT id FROM tags WHERE name = 'Main Course' AND category = 'course')),
    ((SELECT id FROM recipes WHERE slug = 'beef-wellington'), (SELECT id FROM tags WHERE name = 'Advanced' AND category = 'difficulty')),
    ((SELECT id FROM recipes WHERE slug = 'beef-wellington'), (SELECT id FROM tags WHERE name = 'Roasting' AND category = 'technique')),
    ((SELECT id FROM recipes WHERE slug = 'beef-wellington'), (SELECT id FROM tags WHERE name = 'Winter' AND category = 'season'));

-- Assign tags to Simple Roast Chicken
INSERT INTO recipe_tags (recipe_id, tag_id) VALUES
    ((SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'), (SELECT id FROM tags WHERE name = 'American' AND category = 'cuisine')),
    ((SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'), (SELECT id FROM tags WHERE name = 'Dinner' AND category = 'meal_type')),
    ((SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'), (SELECT id FROM tags WHERE name = 'Main Course' AND category = 'course')),
    ((SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'), (SELECT id FROM tags WHERE name = 'Easy' AND category = 'difficulty')),
    ((SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'), (SELECT id FROM tags WHERE name = 'Roasting' AND category = 'technique')),
    ((SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'), (SELECT id FROM tags WHERE name = 'Year-Round' AND category = 'season'));
