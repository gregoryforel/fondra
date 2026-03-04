package domain

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// CompiledStep represents a step in the compiled recipe.
type CompiledStep struct {
	Position       int                 `json:"position"`
	Instruction    string              `json:"instruction"`
	ActiveSeconds  int                 `json:"active_seconds"`
	PassiveSeconds int                 `json:"passive_seconds"`
	Components     []CompiledComponent `json:"components"`
}

// CompiledComponent represents a component in a compiled step.
type CompiledComponent struct {
	Name            string  `json:"name"`
	Quantity        float64 `json:"quantity"`
	Unit            string  `json:"unit"`
	Optional        bool    `json:"optional"`
	PreparationNote string  `json:"preparation_note,omitempty"`
	IsSubRecipe     bool    `json:"is_sub_recipe"`
}

// GroceryItem represents a consolidated grocery list item.
type GroceryItem struct {
	IngredientID    string   `json:"ingredient_id"`
	Name            string   `json:"name"`
	TotalQuantity   float64  `json:"total_quantity"`
	Unit            string   `json:"unit"`
	Allergens       []string `json:"allergens,omitempty"`
	SubRecipeSource string   `json:"sub_recipe_source,omitempty"`
}

// NutritionInfo holds nutrition data.
type NutritionInfo struct {
	Calories      float64            `json:"calories"`
	ProteinG      float64            `json:"protein_g"`
	FatG          float64            `json:"fat_g"`
	SaturatedG    float64            `json:"saturated_fat_g"`
	CarbsG        float64            `json:"carbs_g"`
	FiberG        float64            `json:"fiber_g"`
	SugarG        float64            `json:"sugar_g"`
	SodiumMg      float64            `json:"sodium_mg"`
	CholesterolMg float64            `json:"cholesterol_mg"`
	Vitamins      map[string]float64 `json:"vitamins,omitempty"`
	Minerals      map[string]float64 `json:"minerals,omitempty"`
}

// CompileRecipe resolves the sub-recipe DAG and compiles all data into compiled_recipes.
func CompileRecipe(ctx context.Context, pool *pgxpool.Pool, recipeID string) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// 1. Get recipe metadata
	var servings int
	err = tx.QueryRow(ctx, "SELECT servings FROM recipes WHERE id = $1", recipeID).Scan(&servings)
	if err != nil {
		return fmt.Errorf("get recipe: %w", err)
	}
	if servings == 0 {
		servings = 1
	}

	// 2. Compile steps with their components
	compiledSteps, err := compileSteps(ctx, tx, recipeID)
	if err != nil {
		return fmt.Errorf("compile steps: %w", err)
	}

	// 3. Resolve DAG and aggregate grocery list
	groceryList, err := resolveGroceryList(ctx, tx, recipeID)
	if err != nil {
		return fmt.Errorf("resolve grocery list: %w", err)
	}

	// 4. Collect allergens
	allergens, err := collectAllergens(ctx, tx, recipeID)
	if err != nil {
		return fmt.Errorf("collect allergens: %w", err)
	}

	// 5. Determine diet compatibility
	dietFlags, err := collectDietFlags(ctx, tx, recipeID)
	if err != nil {
		return fmt.Errorf("collect diet flags: %w", err)
	}

	// 6. Collect tags
	tags, err := collectTags(ctx, tx, recipeID)
	if err != nil {
		return fmt.Errorf("collect tags: %w", err)
	}

	// 7. Sum timing
	totalActive, totalPassive := sumTiming(compiledSteps)

	// 8. Nutrition rollup
	nutritionTotal := computeNutrition(ctx, tx, groceryList)
	nutritionPerServing := scaleNutrition(nutritionTotal, servings)

	// 9. Write to compiled_recipes
	stepsJSON, _ := json.Marshal(compiledSteps)
	groceryJSON, _ := json.Marshal(groceryList)
	nutritionPerServingJSON, _ := json.Marshal(nutritionPerServing)
	nutritionTotalJSON, _ := json.Marshal(nutritionTotal)

	_, err = tx.Exec(ctx, `
		INSERT INTO compiled_recipes (
			recipe_id, compiled_at, is_stale,
			compiled_steps, compiled_grocery_list,
			compiled_nutrition_per_serving, compiled_nutrition_total,
			compiled_allergens, compiled_diet_flags,
			total_active_seconds, total_passive_seconds, total_calories_per_serving,
			compiled_tags
		) VALUES ($1, now(), false, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		ON CONFLICT (recipe_id) DO UPDATE SET
			compiled_at = now(),
			is_stale = false,
			compiled_steps = EXCLUDED.compiled_steps,
			compiled_grocery_list = EXCLUDED.compiled_grocery_list,
			compiled_nutrition_per_serving = EXCLUDED.compiled_nutrition_per_serving,
			compiled_nutrition_total = EXCLUDED.compiled_nutrition_total,
			compiled_allergens = EXCLUDED.compiled_allergens,
			compiled_diet_flags = EXCLUDED.compiled_diet_flags,
			total_active_seconds = EXCLUDED.total_active_seconds,
			total_passive_seconds = EXCLUDED.total_passive_seconds,
			total_calories_per_serving = EXCLUDED.total_calories_per_serving,
			compiled_tags = EXCLUDED.compiled_tags
	`, recipeID, stepsJSON, groceryJSON,
		nutritionPerServingJSON, nutritionTotalJSON,
		allergens, dietFlags,
		totalActive, totalPassive, nutritionPerServing.Calories,
		tags)
	if err != nil {
		return fmt.Errorf("upsert compiled recipe: %w", err)
	}

	return tx.Commit(ctx)
}

func compileSteps(ctx context.Context, tx pgx.Tx, recipeID string) ([]CompiledStep, error) {
	rows, err := tx.Query(ctx, `
		SELECT rs.position, rs.instruction, rs.active_seconds, rs.passive_seconds,
		       rsc.ingredient_id, rsc.sub_recipe_id, rsc.quantity,
		       u.name AS unit_name, rsc.optional, rsc.preparation_note,
		       COALESCE(i.name, sr.title, '') AS component_name
		FROM recipe_steps rs
		LEFT JOIN recipe_step_components rsc ON rsc.step_id = rs.id
		LEFT JOIN units u ON u.id = rsc.unit_id
		LEFT JOIN ingredients i ON i.id = rsc.ingredient_id
		LEFT JOIN recipes sr ON sr.id = rsc.sub_recipe_id
		WHERE rs.recipe_id = $1
		ORDER BY rs.position, rsc.position
	`, recipeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	stepMap := make(map[int]*CompiledStep)
	var stepOrder []int

	for rows.Next() {
		var position int
		var instruction string
		var activeSec, passiveSec int
		var ingredientID, subRecipeID, unitName, prepNote, componentName *string
		var quantity *float64
		var optional *bool

		err := rows.Scan(&position, &instruction, &activeSec, &passiveSec,
			&ingredientID, &subRecipeID, &quantity,
			&unitName, &optional, &prepNote, &componentName)
		if err != nil {
			return nil, err
		}

		step, exists := stepMap[position]
		if !exists {
			step = &CompiledStep{
				Position:       position,
				Instruction:    instruction,
				ActiveSeconds:  activeSec,
				PassiveSeconds: passiveSec,
				Components:     []CompiledComponent{},
			}
			stepMap[position] = step
			stepOrder = append(stepOrder, position)
		}

		if componentName != nil && *componentName != "" {
			comp := CompiledComponent{
				Name:        *componentName,
				IsSubRecipe: subRecipeID != nil,
			}
			if quantity != nil {
				comp.Quantity = *quantity
			}
			if unitName != nil {
				comp.Unit = *unitName
			}
			if optional != nil {
				comp.Optional = *optional
			}
			if prepNote != nil {
				comp.PreparationNote = *prepNote
			}
			step.Components = append(step.Components, comp)
		}
	}

	result := make([]CompiledStep, 0, len(stepOrder))
	for _, pos := range stepOrder {
		result = append(result, *stepMap[pos])
	}
	return result, nil
}

func resolveGroceryList(ctx context.Context, tx pgx.Tx, recipeID string) ([]GroceryItem, error) {
	rows, err := tx.Query(ctx, `
		WITH RECURSIVE recipe_tree AS (
			SELECT
				rsc.ingredient_id,
				rsc.sub_recipe_id,
				rsc.quantity,
				rsc.unit_id,
				1.0::numeric AS multiplier
			FROM recipe_steps rs
			JOIN recipe_step_components rsc ON rsc.step_id = rs.id
			WHERE rs.recipe_id = $1

			UNION ALL

			SELECT
				rsc.ingredient_id,
				rsc.sub_recipe_id,
				rsc.quantity,
				rsc.unit_id,
				rt.multiplier * (rt.quantity / NULLIF(COALESCE(r.yield_amount, r.servings::numeric), 0))
			FROM recipe_tree rt
			JOIN recipes r ON r.id = rt.sub_recipe_id
			JOIN recipe_steps rs ON rs.recipe_id = r.id
			JOIN recipe_step_components rsc ON rsc.step_id = rs.id
			WHERE rt.sub_recipe_id IS NOT NULL
		),
		normalized AS (
			SELECT
				rt.ingredient_id,
				COALESCE(i.default_unit_id, rt.unit_id) AS unit_id,
				CASE
					WHEN rt.unit_id = COALESCE(i.default_unit_id, rt.unit_id) THEN
						rt.quantity * rt.multiplier
					WHEN su.dimension = du.dimension THEN
						rt.quantity * rt.multiplier * su.to_base_factor / NULLIF(du.to_base_factor, 0)
					WHEN su.dimension = 'volume' AND du.dimension = 'mass' AND id_dens.density_g_per_ml IS NOT NULL THEN
						rt.quantity * rt.multiplier * su.to_base_factor * id_dens.density_g_per_ml / NULLIF(du.to_base_factor, 0)
					WHEN su.dimension = 'mass' AND du.dimension = 'volume' AND id_dens.density_g_per_ml IS NOT NULL THEN
						rt.quantity * rt.multiplier * su.to_base_factor / id_dens.density_g_per_ml / NULLIF(du.to_base_factor, 0)
					ELSE
						rt.quantity * rt.multiplier
				END AS converted_quantity
			FROM recipe_tree rt
			JOIN ingredients i ON i.id = rt.ingredient_id
			JOIN units su ON su.id = rt.unit_id
			LEFT JOIN units du ON du.id = i.default_unit_id
			LEFT JOIN ingredient_densities id_dens ON id_dens.ingredient_id = rt.ingredient_id AND id_dens.notes IS NULL
			WHERE rt.ingredient_id IS NOT NULL
		)
		SELECT
			n.ingredient_id,
			i.name,
			u.name AS unit_name,
			SUM(n.converted_quantity) AS total_quantity
		FROM normalized n
		JOIN ingredients i ON i.id = n.ingredient_id
		JOIN units u ON u.id = n.unit_id
		GROUP BY n.ingredient_id, i.name, n.unit_id, u.name
		ORDER BY i.name
	`, recipeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []GroceryItem
	for rows.Next() {
		var item GroceryItem
		err := rows.Scan(&item.IngredientID, &item.Name, &item.Unit, &item.TotalQuantity)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	rows.Close()

	// Fetch allergens in a separate loop to avoid "conn busy"
	for i := range items {
		allergenRows, err := tx.Query(ctx, `
			SELECT a.name FROM ingredient_allergens ia
			JOIN allergens a ON a.id = ia.allergen_id
			WHERE ia.ingredient_id = $1 AND ia.severity = 'contains'
		`, items[i].IngredientID)
		if err != nil {
			return nil, err
		}
		for allergenRows.Next() {
			var name string
			if err := allergenRows.Scan(&name); err != nil {
				allergenRows.Close()
				return nil, err
			}
			items[i].Allergens = append(items[i].Allergens, name)
		}
		allergenRows.Close()
	}

	if items == nil {
		items = []GroceryItem{}
	}
	return items, nil
}

func collectAllergens(ctx context.Context, tx pgx.Tx, recipeID string) ([]string, error) {
	rows, err := tx.Query(ctx, `
		WITH RECURSIVE recipe_tree AS (
			SELECT rsc.ingredient_id, rsc.sub_recipe_id, 1.0::numeric AS multiplier, rsc.quantity
			FROM recipe_steps rs
			JOIN recipe_step_components rsc ON rsc.step_id = rs.id
			WHERE rs.recipe_id = $1
			UNION ALL
			SELECT rsc.ingredient_id, rsc.sub_recipe_id,
				   rt.multiplier * (rt.quantity / NULLIF(COALESCE(r.yield_amount, r.servings::numeric), 0)),
				   rsc.quantity
			FROM recipe_tree rt
			JOIN recipes r ON r.id = rt.sub_recipe_id
			JOIN recipe_steps rs ON rs.recipe_id = r.id
			JOIN recipe_step_components rsc ON rsc.step_id = rs.id
			WHERE rt.sub_recipe_id IS NOT NULL
		)
		SELECT DISTINCT a.name
		FROM recipe_tree rt
		JOIN ingredient_allergens ia ON ia.ingredient_id = rt.ingredient_id
		JOIN allergens a ON a.id = ia.allergen_id
		WHERE rt.ingredient_id IS NOT NULL AND ia.severity = 'contains'
	`, recipeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var allergens []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		allergens = append(allergens, name)
	}
	if allergens == nil {
		allergens = []string{}
	}
	return allergens, nil
}

func collectDietFlags(ctx context.Context, tx pgx.Tx, recipeID string) ([]string, error) {
	rows, err := tx.Query(ctx, `
		WITH RECURSIVE recipe_tree AS (
			SELECT rsc.ingredient_id, rsc.sub_recipe_id, 1.0::numeric AS multiplier, rsc.quantity
			FROM recipe_steps rs
			JOIN recipe_step_components rsc ON rsc.step_id = rs.id
			WHERE rs.recipe_id = $1
			UNION ALL
			SELECT rsc.ingredient_id, rsc.sub_recipe_id,
				   rt.multiplier * (rt.quantity / NULLIF(COALESCE(r.yield_amount, r.servings::numeric), 0)),
				   rsc.quantity
			FROM recipe_tree rt
			JOIN recipes r ON r.id = rt.sub_recipe_id
			JOIN recipe_steps rs ON rs.recipe_id = r.id
			JOIN recipe_step_components rsc ON rsc.step_id = rs.id
			WHERE rt.sub_recipe_id IS NOT NULL
		)
		SELECT df.name
		FROM diet_flags df
		WHERE NOT EXISTS (
			SELECT 1
			FROM recipe_tree rt
			WHERE rt.ingredient_id IS NOT NULL
			AND NOT EXISTS (
				SELECT 1 FROM ingredient_diet_flags idf
				WHERE idf.ingredient_id = rt.ingredient_id
				AND idf.diet_flag_id = df.id
				AND idf.compatible = true
			)
		)
		AND EXISTS (
			SELECT 1
			FROM recipe_tree rt
			WHERE rt.ingredient_id IS NOT NULL
		)
	`, recipeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var flags []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		flags = append(flags, name)
	}
	if flags == nil {
		flags = []string{}
	}
	return flags, nil
}

func collectTags(ctx context.Context, tx pgx.Tx, recipeID string) ([]string, error) {
	rows, err := tx.Query(ctx, `
		SELECT t.name
		FROM recipe_tags rtag
		JOIN tags t ON t.id = rtag.tag_id
		WHERE rtag.recipe_id = $1
		ORDER BY t.category, t.name
	`, recipeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tags []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		tags = append(tags, name)
	}
	if tags == nil {
		tags = []string{}
	}
	return tags, nil
}

func sumTiming(steps []CompiledStep) (int, int) {
	var totalActive, totalPassive int
	for _, s := range steps {
		totalActive += s.ActiveSeconds
		totalPassive += s.PassiveSeconds
	}
	return totalActive, totalPassive
}

// computeNutrition calculates total nutrition from the grocery list.
// TODO: Implement real USDA-based calculation using ingredient_nutrients table.
func computeNutrition(ctx context.Context, tx pgx.Tx, groceryList []GroceryItem) NutritionInfo {
	nutrition := NutritionInfo{
		Vitamins: make(map[string]float64),
		Minerals: make(map[string]float64),
	}

	for _, item := range groceryList {
		// Query nutrient data for this ingredient
		rows, err := tx.Query(ctx, `
			SELECT n.name, n.unit, inu.amount_per_100g
			FROM ingredient_nutrients inu
			JOIN nutrients n ON n.id = inu.nutrient_id
			WHERE inu.ingredient_id = $1
		`, item.IngredientID)
		if err != nil {
			continue
		}

		// Calculate based on quantity (assumed grams for simplicity)
		factor := item.TotalQuantity / 100.0

		for rows.Next() {
			var name, unit string
			var amountPer100g float64
			if err := rows.Scan(&name, &unit, &amountPer100g); err != nil {
				continue
			}
			amount := amountPer100g * factor

			switch name {
			case "Energy":
				nutrition.Calories += amount
			case "Protein":
				nutrition.ProteinG += amount
			case "Total lipid (fat)":
				nutrition.FatG += amount
			case "Fatty acids, total saturated":
				nutrition.SaturatedG += amount
			case "Carbohydrate, by difference":
				nutrition.CarbsG += amount
			case "Fiber, total dietary":
				nutrition.FiberG += amount
			case "Sugars, total including NLEA":
				nutrition.SugarG += amount
			case "Sodium, Na":
				nutrition.SodiumMg += amount
			case "Cholesterol":
				nutrition.CholesterolMg += amount
			case "Calcium, Ca":
				nutrition.Minerals["calcium_mg"] = nutrition.Minerals["calcium_mg"] + amount
			case "Iron, Fe":
				nutrition.Minerals["iron_mg"] = nutrition.Minerals["iron_mg"] + amount
			case "Potassium, K":
				nutrition.Minerals["potassium_mg"] = nutrition.Minerals["potassium_mg"] + amount
			case "Vitamin C, total ascorbic acid":
				nutrition.Vitamins["vitamin_c_mg"] = nutrition.Vitamins["vitamin_c_mg"] + amount
			case "Vitamin A, RAE":
				nutrition.Vitamins["vitamin_a_rae_mcg"] = nutrition.Vitamins["vitamin_a_rae_mcg"] + amount
			}
		}
		rows.Close()
	}

	return nutrition
}

func scaleNutrition(total NutritionInfo, servings int) NutritionInfo {
	if servings <= 0 {
		servings = 1
	}
	s := float64(servings)
	scaled := NutritionInfo{
		Calories:      total.Calories / s,
		ProteinG:      total.ProteinG / s,
		FatG:          total.FatG / s,
		SaturatedG:    total.SaturatedG / s,
		CarbsG:        total.CarbsG / s,
		FiberG:        total.FiberG / s,
		SugarG:        total.SugarG / s,
		SodiumMg:      total.SodiumMg / s,
		CholesterolMg: total.CholesterolMg / s,
		Vitamins:      make(map[string]float64),
		Minerals:      make(map[string]float64),
	}
	for k, v := range total.Vitamins {
		scaled.Vitamins[k] = v / s
	}
	for k, v := range total.Minerals {
		scaled.Minerals[k] = v / s
	}
	return scaled
}

// CompileAllRecipes compiles recipes in the database.
// If staleOnly is true, only recipes marked as stale are recompiled.
func CompileAllRecipes(ctx context.Context, pool *pgxpool.Pool, staleOnly bool) error {
	var query string
	if staleOnly {
		query = "SELECT recipe_id FROM compiled_recipes WHERE is_stale = true ORDER BY compiled_at"
	} else {
		query = "SELECT id FROM recipes ORDER BY created_at"
	}

	rows, err := pool.Query(ctx, query)
	if err != nil {
		return fmt.Errorf("list recipes: %w", err)
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return err
		}
		ids = append(ids, id)
	}

	for _, id := range ids {
		if err := CompileRecipe(ctx, pool, id); err != nil {
			return fmt.Errorf("compile recipe %s: %w", id, err)
		}
	}
	return nil
}
