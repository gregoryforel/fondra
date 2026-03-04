-- Seed: demo user and recipes

-- Demo user
INSERT INTO app_users (display_name, email, preferred_unit_system, preferred_locale)
VALUES ('Demo Chef', 'demo@example.com', 'metric', 'en');

-- ============================================================
-- Recipe 1: Puff Pastry (base recipe, no sub-recipes)
-- ============================================================
INSERT INTO recipes (title, slug, description, servings, visibility, author_id)
VALUES (
    'Classic Puff Pastry',
    'classic-puff-pastry',
    'Flaky, buttery puff pastry from scratch. A foundational recipe used in many dishes.',
    1,  -- yields ~1kg of dough, "1 batch"
    'public',
    (SELECT id FROM app_users WHERE email = 'demo@example.com')
);

-- Step 1: Mix dough
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'),
    1,
    'Combine flour, salt, and 30g of butter (melted) in a large bowl. Add cold water gradually and mix until a smooth dough forms. Do not overwork.',
    600, -- 10 min active
    0
);

INSERT INTO recipe_step_components (step_id, position, ingredient_id, quantity, unit_id)
VALUES
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry') AND position = 1),
     1, (SELECT id FROM ingredients WHERE name_slug = 'all-purpose-flour'), 500, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry') AND position = 1),
     2, (SELECT id FROM ingredients WHERE name_slug = 'salt-table'), 10, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry') AND position = 1),
     3, (SELECT id FROM ingredients WHERE name_slug = 'butter-unsalted'), 30, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry') AND position = 1),
     4, (SELECT id FROM ingredients WHERE name_slug = 'water'), 250, (SELECT id FROM units WHERE name = 'ml'));

-- Step 2: Rest dough
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'),
    2,
    'Wrap dough in cling film and refrigerate for 30 minutes.',
    60,   -- 1 min wrapping
    1800  -- 30 min resting
);

-- Step 3: Prepare butter block
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'),
    3,
    'Place remaining butter between two sheets of parchment paper. Pound with a rolling pin into a 15cm square, about 1cm thick. Refrigerate until firm but pliable.',
    300,  -- 5 min
    600   -- 10 min chilling
);

INSERT INTO recipe_step_components (step_id, position, ingredient_id, quantity, unit_id)
VALUES
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry') AND position = 3),
     1, (SELECT id FROM ingredients WHERE name_slug = 'butter-unsalted'), 330, (SELECT id FROM units WHERE name = 'g'));

-- Step 4: Laminate (fold and turn)
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'),
    4,
    'Roll dough into a rectangle, place butter block in center, fold dough over butter. Roll out and perform 6 single folds, resting 30 minutes in the fridge between every 2 folds.',
    1800, -- 30 min active rolling
    5400  -- 90 min total resting (3 x 30 min)
);

-- Step 5: Final rest
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'),
    5,
    'Wrap finished dough and refrigerate for at least 1 hour before using.',
    60,
    3600  -- 1 hour
);


-- ============================================================
-- Recipe 2: Beef Wellington (references Puff Pastry as sub-recipe)
-- ============================================================
INSERT INTO recipes (title, slug, description, servings, visibility, author_id)
VALUES (
    'Beef Wellington',
    'beef-wellington',
    'Tender beef tenderloin wrapped in mushroom duxelles and golden puff pastry.',
    4,
    'public',
    (SELECT id FROM app_users WHERE email = 'demo@example.com')
);

-- Step 1: Sear the beef
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'beef-wellington'),
    1,
    'Season beef with salt and pepper. Heat olive oil in a cast iron pan over high heat. Sear beef on all sides until deeply browned, about 2 minutes per side. Remove and let cool.',
    600,  -- 10 min
    300   -- 5 min cooling
);

INSERT INTO recipe_step_components (step_id, position, ingredient_id, quantity, unit_id)
VALUES
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 1),
     1, (SELECT id FROM ingredients WHERE name_slug = 'beef-tenderloin-raw'), 800, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 1),
     2, (SELECT id FROM ingredients WHERE name_slug = 'salt-table'), 8, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 1),
     3, (SELECT id FROM ingredients WHERE name_slug = 'black-pepper'), 3, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 1),
     4, (SELECT id FROM ingredients WHERE name_slug = 'olive-oil'), 15, (SELECT id FROM units WHERE name = 'ml'));

-- Step 2: Make duxelles
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'beef-wellington'),
    2,
    'Finely chop mushrooms, onion, and garlic. Cook in butter over medium heat until all moisture evaporates and mixture is dry and deeply flavored, about 15 minutes. Stir in thyme and Dijon mustard. Season with salt. Let cool completely.',
    1200,  -- 20 min
    600    -- 10 min cooling
);

INSERT INTO recipe_step_components (step_id, position, ingredient_id, quantity, unit_id)
VALUES
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 2),
     1, (SELECT id FROM ingredients WHERE name_slug = 'mushrooms-white-raw'), 400, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 2),
     2, (SELECT id FROM ingredients WHERE name_slug = 'onion-raw'), 100, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 2),
     3, (SELECT id FROM ingredients WHERE name_slug = 'garlic-raw'), 10, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 2),
     4, (SELECT id FROM ingredients WHERE name_slug = 'butter-unsalted'), 30, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 2),
     5, (SELECT id FROM ingredients WHERE name_slug = 'thyme-fresh'), 5, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 2),
     6, (SELECT id FROM ingredients WHERE name_slug = 'dijon-mustard'), 15, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 2),
     7, (SELECT id FROM ingredients WHERE name_slug = 'salt-table'), 3, (SELECT id FROM units WHERE name = 'g'));

-- Step 3: Wrap in pastry (sub-recipe reference!)
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'beef-wellington'),
    3,
    'Roll out puff pastry to about 3mm thickness. Spread duxelles evenly, leaving a 2cm border. Place seared beef in the center. Brush egg wash on borders. Roll pastry tightly around beef, sealing edges. Brush entire surface with egg wash. Refrigerate for 30 minutes.',
    900,  -- 15 min
    1800  -- 30 min chilling
);

INSERT INTO recipe_step_components (step_id, position, ingredient_id, sub_recipe_id, quantity, unit_id)
VALUES
    -- Sub-recipe reference: Puff Pastry (1 batch = servings of puff pastry recipe)
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 3),
     1, NULL, (SELECT id FROM recipes WHERE slug = 'classic-puff-pastry'), 1, (SELECT id FROM units WHERE name = 'piece')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'beef-wellington') AND position = 3),
     2, (SELECT id FROM ingredients WHERE name_slug = 'eggs-whole-raw'), NULL, 1, (SELECT id FROM units WHERE name = 'piece'));

-- Step 4: Bake
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'beef-wellington'),
    4,
    'Preheat oven to 220°C (425°F). Score the pastry top in a decorative pattern. Bake for 25-30 minutes until pastry is deep golden and internal temperature of beef reaches 52°C (125°F) for medium-rare. Rest for 10 minutes before slicing.',
    120,   -- 2 min scoring/placing in oven
    2400   -- 40 min (30 bake + 10 rest)
);


-- ============================================================
-- Recipe 3: Simple Roast Chicken (flat, no sub-recipes)
-- ============================================================
INSERT INTO recipes (title, slug, description, servings, visibility, author_id)
VALUES (
    'Simple Roast Chicken',
    'simple-roast-chicken',
    'A perfectly roasted whole chicken with crispy skin, lemon, and thyme. Simple, classic, foolproof.',
    4,
    'public',
    (SELECT id FROM app_users WHERE email = 'demo@example.com')
);

-- Step 1: Prep the chicken
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'),
    1,
    'Preheat oven to 200°C (400°F). Pat chicken dry with paper towels. Rub with olive oil, then season generously with salt and pepper inside and out.',
    300,  -- 5 min
    0
);

INSERT INTO recipe_step_components (step_id, position, ingredient_id, quantity, unit_id)
VALUES
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken') AND position = 1),
     1, (SELECT id FROM ingredients WHERE name_slug = 'chicken-breast-raw'), 1500, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken') AND position = 1),
     2, (SELECT id FROM ingredients WHERE name_slug = 'olive-oil'), 30, (SELECT id FROM units WHERE name = 'ml')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken') AND position = 1),
     3, (SELECT id FROM ingredients WHERE name_slug = 'salt-table'), 12, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken') AND position = 1),
     4, (SELECT id FROM ingredients WHERE name_slug = 'black-pepper'), 3, (SELECT id FROM units WHERE name = 'g'));

-- Step 2: Stuff and roast
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'),
    2,
    'Halve the lemon and stuff inside the cavity along with thyme sprigs and garlic. Place chicken in roasting pan. Scatter onion quarters around the chicken.',
    300,  -- 5 min
    0
);

INSERT INTO recipe_step_components (step_id, position, ingredient_id, quantity, unit_id)
VALUES
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken') AND position = 2),
     1, (SELECT id FROM ingredients WHERE name_slug = 'lemon-raw'), 1, (SELECT id FROM units WHERE name = 'piece')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken') AND position = 2),
     2, (SELECT id FROM ingredients WHERE name_slug = 'thyme-fresh'), 10, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken') AND position = 2),
     3, (SELECT id FROM ingredients WHERE name_slug = 'garlic-raw'), 20, (SELECT id FROM units WHERE name = 'g')),
    ((SELECT id FROM recipe_steps WHERE recipe_id = (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken') AND position = 2),
     4, (SELECT id FROM ingredients WHERE name_slug = 'onion-raw'), 200, (SELECT id FROM units WHERE name = 'g'));

-- Step 3: Roast
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'),
    3,
    'Roast for 1 hour 15 minutes, or until juices run clear and internal temperature reaches 74°C (165°F). Baste with pan juices every 20 minutes.',
    300,   -- 5 min basting total
    4500   -- 75 min roasting
);

-- Step 4: Rest and serve
INSERT INTO recipe_steps (recipe_id, position, instruction, active_seconds, passive_seconds)
VALUES (
    (SELECT id FROM recipes WHERE slug = 'simple-roast-chicken'),
    4,
    'Remove from oven, tent loosely with foil, and rest for 15 minutes. Carve and serve with pan juices.',
    180,   -- 3 min carving
    900    -- 15 min resting
);
