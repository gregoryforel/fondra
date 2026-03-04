package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/gregoryforel/recipe-platform/internal/convert"
	"github.com/gregoryforel/recipe-platform/internal/middleware"
	"github.com/gregoryforel/recipe-platform/web/templates"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Handler holds dependencies for HTTP handlers.
type Handler struct {
	DB     *pgxpool.Pool
	Logger *slog.Logger
}

// New creates a new Handler.
func New(db *pgxpool.Pool, logger *slog.Logger) *Handler {
	return &Handler{DB: db, Logger: logger}
}

// RegisterRoutes sets up all routes on the given mux.
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", h.HandleHealth)
	mux.HandleFunc("GET /", h.HandleHome)
	mux.HandleFunc("GET /recipes", h.HandleRecipeList)
	mux.HandleFunc("GET /recipes/{slug}", h.HandleRecipeDetail)
	mux.HandleFunc("GET /recipes/partial/list", h.HandleRecipeListPartial)

	// API endpoints (JSON for future Flutter app)
	mux.HandleFunc("GET /api/v1/recipes", h.HandleAPIRecipeList)
	mux.HandleFunc("GET /api/v1/recipes/{slug}", h.HandleAPIRecipeDetail)

	// Static files
	mux.Handle("GET /static/", http.StripPrefix("/static/", http.FileServer(http.Dir("web/static"))))
}

// HandleHealth returns 200 if the process is alive.
// This is intentionally independent of database state so the container
// healthcheck passes while the DB is still starting up.
func (h *Handler) HandleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// HandleHome renders the home page with featured recipes.
func (h *Handler) HandleHome(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	recipes, err := h.listCompiledRecipes(r.Context(), 10, 0, "")
	if err != nil {
		h.Logger.Error("failed to list recipes", "error", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	data := templates.HomeData{Recipes: recipes}
	templates.Home(data).Render(r.Context(), w)
}

// HandleRecipeList renders the full recipe list page.
func (h *Handler) HandleRecipeList(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	recipes, err := h.listCompiledRecipes(r.Context(), 50, 0, query)
	if err != nil {
		h.Logger.Error("failed to list recipes", "error", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	data := templates.RecipeListData{Recipes: recipes, Query: query}
	templates.RecipeList(data).Render(r.Context(), w)
}

// HandleRecipeListPartial returns just the recipe cards HTML fragment for htmx.
func (h *Handler) HandleRecipeListPartial(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	recipes, err := h.listCompiledRecipes(r.Context(), 50, 0, query)
	if err != nil {
		h.Logger.Error("failed to search recipes", "error", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	templates.RecipeListPartial(recipes).Render(r.Context(), w)
}

// HandleRecipeDetail renders a single recipe page.
func (h *Handler) HandleRecipeDetail(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	if slug == "" {
		http.NotFound(w, r)
		return
	}

	unitSystem := middleware.GetUnitSystem(r.Context())

	data, err := h.getRecipeDetail(r.Context(), slug, unitSystem)
	if err != nil {
		h.Logger.Error("failed to get recipe", "error", err, "slug", slug)
		http.NotFound(w, r)
		return
	}

	templates.RecipeDetail(*data).Render(r.Context(), w)
}

// HandleAPIRecipeList returns JSON list of recipes.
func (h *Handler) HandleAPIRecipeList(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	recipes, err := h.listCompiledRecipesJSON(r.Context(), 50, 0, query)
	if err != nil {
		h.Logger.Error("failed to list recipes", "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"recipes": recipes})
}

// HandleAPIRecipeDetail returns JSON detail of a single recipe.
func (h *Handler) HandleAPIRecipeDetail(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	if slug == "" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
		return
	}

	recipe, err := h.getCompiledRecipeJSON(r.Context(), slug)
	if err != nil {
		h.Logger.Error("failed to get recipe", "error", err, "slug", slug)
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
		return
	}

	writeJSON(w, http.StatusOK, recipe)
}

func (h *Handler) listCompiledRecipes(ctx context.Context, limit, offset int, query string) ([]templates.RecipeCardData, error) {
	var rows interface{ Next() bool }
	var err error

	const compiledRecipeCardCols = `
			cr.recipe_id, cr.compiled_at, cr.is_stale,
			cr.compiled_steps, cr.compiled_grocery_list,
			cr.compiled_nutrition_per_serving, cr.compiled_nutrition_total,
			cr.compiled_allergens, cr.compiled_diet_flags,
			cr.total_active_seconds, cr.total_passive_seconds, cr.total_calories_per_serving,
			cr.compiled_tags,
			r.title, r.slug, r.description, r.servings`

	if query != "" {
		r, e := h.DB.Query(ctx, `
			SELECT `+compiledRecipeCardCols+`
			FROM compiled_recipes cr
			JOIN recipes r ON r.id = cr.recipe_id
			WHERE r.visibility = 'public'
			  AND (r.title ILIKE '%' || $1 || '%' OR r.description ILIKE '%' || $1 || '%')
			ORDER BY r.created_at DESC LIMIT $2 OFFSET $3
		`, query, limit, offset)
		rows = r
		err = e
	} else {
		r, e := h.DB.Query(ctx, `
			SELECT `+compiledRecipeCardCols+`
			FROM compiled_recipes cr
			JOIN recipes r ON r.id = cr.recipe_id
			WHERE r.visibility = 'public'
			ORDER BY r.created_at DESC LIMIT $1 OFFSET $2
		`, limit, offset)
		rows = r
		err = e
	}

	if err != nil {
		return nil, err
	}

	type pgxRows interface {
		Next() bool
		Scan(dest ...any) error
		Close()
	}
	pgxR := rows.(pgxRows)
	defer pgxR.Close()

	var recipes []templates.RecipeCardData
	for pgxR.Next() {
		var (
			recipeID                                              string
			compiledAt                                            any
			isStale                                               bool
			compiledSteps, compiledGrocery                        json.RawMessage
			compiledNutritionPerServing, compiledNutritionTotal   json.RawMessage
			compiledAllergens, compiledDietFlags                  []string
			totalActiveSec, totalPassiveSec                       int
			totalCalPerServing                                    *float64
			compiledTags                                          []string
			title, slug                                           string
			description                                           *string
			servings                                              int
		)
		err := pgxR.Scan(
			&recipeID, &compiledAt, &isStale,
			&compiledSteps, &compiledGrocery,
			&compiledNutritionPerServing, &compiledNutritionTotal,
			&compiledAllergens, &compiledDietFlags,
			&totalActiveSec, &totalPassiveSec, &totalCalPerServing,
			&compiledTags,
			&title, &slug, &description, &servings,
		)
		if err != nil {
			return nil, fmt.Errorf("scan recipe: %w", err)
		}

		desc := ""
		if description != nil {
			desc = *description
		}
		cal := 0.0
		if totalCalPerServing != nil {
			cal = *totalCalPerServing
		}

		recipes = append(recipes, templates.RecipeCardData{
			Title:               title,
			Slug:                slug,
			Description:         desc,
			TotalActiveMinutes:  totalActiveSec / 60,
			TotalPassiveMinutes: totalPassiveSec / 60,
			CaloriesPerServing:  cal,
			DietFlags:           compiledDietFlags,
			Allergens:           compiledAllergens,
			Tags:                compiledTags,
			Servings:            servings,
		})
	}

	if recipes == nil {
		recipes = []templates.RecipeCardData{}
	}
	return recipes, nil
}

func (h *Handler) getRecipeDetail(ctx context.Context, slug, unitSystem string) (*templates.RecipeDetailData, error) {
	var (
		recipeID                                              string
		compiledAt                                            any
		isStale                                               bool
		compiledStepsJSON, compiledGroceryJSON                 json.RawMessage
		compiledNutritionPerServingJSON, compiledNutritionTotalJSON json.RawMessage
		compiledAllergens, compiledDietFlags                  []string
		totalActiveSec, totalPassiveSec                       int
		totalCalPerServing                                    *float64
		compiledTags                                          []string
		title, rSlug                                          string
		description                                           *string
		servings                                              int
		yieldAmount                                           *float64
		yieldUnitID                                           *string
	)

	err := h.DB.QueryRow(ctx, `
		SELECT cr.recipe_id, cr.compiled_at, cr.is_stale,
		       cr.compiled_steps, cr.compiled_grocery_list,
		       cr.compiled_nutrition_per_serving, cr.compiled_nutrition_total,
		       cr.compiled_allergens, cr.compiled_diet_flags,
		       cr.total_active_seconds, cr.total_passive_seconds, cr.total_calories_per_serving,
		       cr.compiled_tags,
		       r.title, r.slug, r.description, r.servings, r.yield_amount, r.yield_unit_id
		FROM compiled_recipes cr
		JOIN recipes r ON r.id = cr.recipe_id
		WHERE r.slug = $1
	`, slug).Scan(
		&recipeID, &compiledAt, &isStale,
		&compiledStepsJSON, &compiledGroceryJSON,
		&compiledNutritionPerServingJSON, &compiledNutritionTotalJSON,
		&compiledAllergens, &compiledDietFlags,
		&totalActiveSec, &totalPassiveSec, &totalCalPerServing,
		&compiledTags,
		&title, &rSlug, &description, &servings, &yieldAmount, &yieldUnitID,
	)
	if err != nil {
		return nil, fmt.Errorf("query compiled recipe: %w", err)
	}

	// Parse compiled steps
	var compiledSteps []struct {
		Position       int    `json:"position"`
		Instruction    string `json:"instruction"`
		ActiveSeconds  int    `json:"active_seconds"`
		PassiveSeconds int    `json:"passive_seconds"`
		Components     []struct {
			Name            string  `json:"name"`
			Quantity        float64 `json:"quantity"`
			Unit            string  `json:"unit"`
			Optional        bool    `json:"optional"`
			PreparationNote string  `json:"preparation_note"`
			IsSubRecipe     bool    `json:"is_sub_recipe"`
		} `json:"components"`
	}
	json.Unmarshal(compiledStepsJSON, &compiledSteps)

	// Parse compiled grocery list
	var groceryItems []struct {
		IngredientID  string   `json:"ingredient_id"`
		Name          string   `json:"name"`
		TotalQuantity float64  `json:"total_quantity"`
		Unit          string   `json:"unit"`
		Allergens     []string `json:"allergens"`
	}
	json.Unmarshal(compiledGroceryJSON, &groceryItems)

	// Parse nutrition
	var nutrition struct {
		Calories      float64 `json:"calories"`
		ProteinG      float64 `json:"protein_g"`
		FatG          float64 `json:"fat_g"`
		SaturatedG    float64 `json:"saturated_fat_g"`
		CarbsG        float64 `json:"carbs_g"`
		FiberG        float64 `json:"fiber_g"`
		SugarG        float64 `json:"sugar_g"`
		SodiumMg      float64 `json:"sodium_mg"`
		CholesterolMg float64 `json:"cholesterol_mg"`
	}
	json.Unmarshal(compiledNutritionPerServingJSON, &nutrition)

	// Build template data
	steps := make([]templates.StepData, len(compiledSteps))
	for i, s := range compiledSteps {
		comps := make([]templates.StepComponentData, len(s.Components))
		for j, c := range s.Components {
			comps[j] = templates.StepComponentData{
				Name:            c.Name,
				Quantity:        c.Quantity,
				QuantityUS:      c.Quantity, // TODO: convert using unit data
				Unit:            c.Unit,
				UnitUS:          convertUnitNameForDisplay(c.Unit, c.Quantity),
				Optional:        c.Optional,
				PreparationNote: c.PreparationNote,
				IsSubRecipe:     c.IsSubRecipe,
			}
		}
		steps[i] = templates.StepData{
			Position:       s.Position,
			Instruction:    s.Instruction,
			ActiveSeconds:  s.ActiveSeconds,
			PassiveSeconds: s.PassiveSeconds,
			Components:     comps,
		}
	}

	grocery := make([]templates.GroceryItemData, len(groceryItems))
	for i, g := range groceryItems {
		grocery[i] = templates.GroceryItemData{
			Name:          g.Name,
			TotalQuantity: g.TotalQuantity,
			QuantityUS:    convertQuantityForUS(g.TotalQuantity, g.Unit),
			Unit:          g.Unit,
			UnitUS:        convertUnitNameForDisplay(g.Unit, g.TotalQuantity),
			Allergens:     g.Allergens,
		}
	}

	desc := ""
	if description != nil {
		desc = *description
	}

	// Build yield description
	var yieldDesc string
	if yieldAmount != nil && *yieldAmount > 0 {
		// Look up yield unit name if we have a unit ID
		if yieldUnitID != nil {
			var unitName string
			err := h.DB.QueryRow(ctx, "SELECT name FROM units WHERE id = $1", *yieldUnitID).Scan(&unitName)
			if err == nil {
				yieldDesc = fmt.Sprintf("%.0f %s", *yieldAmount, unitName)
			} else {
				yieldDesc = fmt.Sprintf("%.0f", *yieldAmount)
			}
		} else {
			yieldDesc = fmt.Sprintf("%.0f", *yieldAmount)
		}
	}

	return &templates.RecipeDetailData{
		Title:               title,
		Slug:                rSlug,
		Description:         desc,
		Servings:            servings,
		YieldDescription:    yieldDesc,
		TotalActiveMinutes:  totalActiveSec / 60,
		TotalPassiveMinutes: totalPassiveSec / 60,
		Steps:               steps,
		GroceryList:         grocery,
		Nutrition: templates.NutritionData{
			Calories:      nutrition.Calories,
			ProteinG:      nutrition.ProteinG,
			FatG:          nutrition.FatG,
			SaturatedG:    nutrition.SaturatedG,
			CarbsG:        nutrition.CarbsG,
			FiberG:        nutrition.FiberG,
			SugarG:        nutrition.SugarG,
			SodiumMg:      nutrition.SodiumMg,
			CholesterolMg: nutrition.CholesterolMg,
		},
		DietFlags:  compiledDietFlags,
		Allergens:  compiledAllergens,
		Tags:       compiledTags,
		UnitSystem: unitSystem,
	}, nil
}

// convertQuantityForUS does a simple metric→US conversion for display.
func convertQuantityForUS(quantity float64, unit string) float64 {
	switch unit {
	case "g":
		return convert.RoundForDisplay(quantity / 28.3495) // grams to oz
	case "ml":
		return convert.RoundForDisplay(quantity / 29.5735) // ml to fl oz
	case "kg":
		return convert.RoundForDisplay(quantity * 2.20462) // kg to lb
	case "l":
		return convert.RoundForDisplay(quantity * 4.22675) // l to cups
	default:
		return quantity
	}
}

func convertUnitNameForDisplay(unit string, _ float64) string {
	switch unit {
	case "g":
		return "oz"
	case "ml":
		return "fl oz"
	case "kg":
		return "lb"
	case "l":
		return "cups"
	default:
		return unit
	}
}

func (h *Handler) listCompiledRecipesJSON(ctx context.Context, limit, offset int, query string) ([]map[string]any, error) {
	var sqlStr string
	var args []any

	if query != "" {
		sqlStr = `
			SELECT cr.recipe_id, r.title, r.slug, r.description, r.servings,
			       r.yield_amount, r.yield_unit_id,
			       cr.compiled_allergens, cr.compiled_diet_flags, cr.compiled_tags,
			       cr.total_active_seconds, cr.total_passive_seconds,
			       cr.total_calories_per_serving,
			       cr.compiled_nutrition_per_serving
			FROM compiled_recipes cr
			JOIN recipes r ON r.id = cr.recipe_id
			WHERE r.visibility = 'public'
			  AND (r.title ILIKE '%' || $1 || '%' OR r.description ILIKE '%' || $1 || '%')
			ORDER BY r.created_at DESC LIMIT $2 OFFSET $3`
		args = []any{query, limit, offset}
	} else {
		sqlStr = `
			SELECT cr.recipe_id, r.title, r.slug, r.description, r.servings,
			       r.yield_amount, r.yield_unit_id,
			       cr.compiled_allergens, cr.compiled_diet_flags, cr.compiled_tags,
			       cr.total_active_seconds, cr.total_passive_seconds,
			       cr.total_calories_per_serving,
			       cr.compiled_nutrition_per_serving
			FROM compiled_recipes cr
			JOIN recipes r ON r.id = cr.recipe_id
			WHERE r.visibility = 'public'
			ORDER BY r.created_at DESC LIMIT $1 OFFSET $2`
		args = []any{limit, offset}
	}

	rows, err := h.DB.Query(ctx, sqlStr, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var recipes []map[string]any
	for rows.Next() {
		var (
			id, title, slug       string
			description           *string
			servings              int
			yieldAmount           *float64
			yieldUnitID           *string
			allergens, diets, tags []string
			activeSec, passiveSec int
			calPerServing         *float64
			nutritionJSON         json.RawMessage
		)
		err := rows.Scan(&id, &title, &slug, &description, &servings,
			&yieldAmount, &yieldUnitID,
			&allergens, &diets, &tags, &activeSec, &passiveSec, &calPerServing, &nutritionJSON)
		if err != nil {
			return nil, err
		}

		recipe := map[string]any{
			"id":                     id,
			"title":                  title,
			"slug":                   slug,
			"servings":               servings,
			"allergens":              allergens,
			"diet_flags":             diets,
			"tags":                   tags,
			"total_active_seconds":   activeSec,
			"total_passive_seconds":  passiveSec,
		}
		if description != nil {
			recipe["description"] = *description
		}
		if yieldAmount != nil {
			recipe["yield_amount"] = *yieldAmount
		}
		if yieldUnitID != nil {
			recipe["yield_unit_id"] = *yieldUnitID
		}
		if calPerServing != nil {
			recipe["calories_per_serving"] = *calPerServing
		}
		var nutrition any
		if json.Unmarshal(nutritionJSON, &nutrition) == nil {
			recipe["nutrition_per_serving"] = nutrition
		}

		recipes = append(recipes, recipe)
	}
	if recipes == nil {
		recipes = []map[string]any{}
	}
	return recipes, nil
}

func (h *Handler) getCompiledRecipeJSON(ctx context.Context, slug string) (map[string]any, error) {
	var (
		id                                    string
		compiledSteps, compiledGrocery        json.RawMessage
		nutritionPerServing, nutritionTotal   json.RawMessage
		allergens, diets, tags                []string
		activeSec, passiveSec                 int
		calPerServing                         *float64
		title, rSlug                          string
		description                           *string
		servings                              int
		yieldAmount                           *float64
		yieldUnitID                           *string
	)

	err := h.DB.QueryRow(ctx, `
		SELECT cr.recipe_id, r.title, r.slug, r.description, r.servings,
		       r.yield_amount, r.yield_unit_id,
		       cr.compiled_steps, cr.compiled_grocery_list,
		       cr.compiled_nutrition_per_serving, cr.compiled_nutrition_total,
		       cr.compiled_allergens, cr.compiled_diet_flags, cr.compiled_tags,
		       cr.total_active_seconds, cr.total_passive_seconds,
		       cr.total_calories_per_serving
		FROM compiled_recipes cr
		JOIN recipes r ON r.id = cr.recipe_id
		WHERE r.slug = $1
	`, slug).Scan(&id, &title, &rSlug, &description, &servings,
		&yieldAmount, &yieldUnitID,
		&compiledSteps, &compiledGrocery,
		&nutritionPerServing, &nutritionTotal,
		&allergens, &diets, &tags,
		&activeSec, &passiveSec, &calPerServing)
	if err != nil {
		return nil, err
	}

	recipe := map[string]any{
		"id":                     id,
		"title":                  title,
		"slug":                   rSlug,
		"servings":               servings,
		"allergens":              allergens,
		"diet_flags":             diets,
		"tags":                   tags,
		"total_active_seconds":   activeSec,
		"total_passive_seconds":  passiveSec,
	}
	if description != nil {
		recipe["description"] = *description
	}
	if yieldAmount != nil {
		recipe["yield_amount"] = *yieldAmount
	}
	if yieldUnitID != nil {
		recipe["yield_unit_id"] = *yieldUnitID
	}
	if calPerServing != nil {
		recipe["calories_per_serving"] = *calPerServing
	}

	var steps, grocery, nutrPerServing, nutrTotal any
	json.Unmarshal(compiledSteps, &steps)
	json.Unmarshal(compiledGrocery, &grocery)
	json.Unmarshal(nutritionPerServing, &nutrPerServing)
	json.Unmarshal(nutritionTotal, &nutrTotal)

	recipe["steps"] = steps
	recipe["grocery_list"] = grocery
	recipe["nutrition_per_serving"] = nutrPerServing
	recipe["nutrition_total"] = nutrTotal

	return recipe, nil
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
