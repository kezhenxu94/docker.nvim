---@param title string
---@param on_choice fun(confirmed: boolean)
return function(title, on_choice)
  vim.ui.select({ "Yes", "No" }, { prompt = title }, function(choice)
    on_choice(choice == "Yes")
  end)
end
