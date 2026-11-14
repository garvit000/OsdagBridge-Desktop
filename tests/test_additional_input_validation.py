"""Regression coverage for empty Additional Inputs on current and inactive tabs."""
import os
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import pytest
from PySide6.QtWidgets import QApplication, QDialog, QLineEdit, QTabWidget, QVBoxLayout, QWidget
from osdagbridge_desktop.ui.dialogs.additional_input import additional_inputs as module


class ValidationDialog(module.AdditionalInputs):
    def __init__(self, key, text, tab_index, saved_value):
        QDialog.__init__(self)
        self.validator = module.BridgeInputValidator()
        self.working_input_dict = {key: saved_value}
        self.default_input_dict = dict(self.working_input_dict)
        self.tabs = QTabWidget(self)
        QVBoxLayout(self).addWidget(self.tabs)
        for title in ("Deck", "Railing"):
            page = QWidget()
            QVBoxLayout(page)
            self.tabs.addTab(page, title)
        container = QWidget()
        QVBoxLayout(container)
        self.tabs.widget(tab_index).layout().addWidget(container)
        self.field = QLineEdit(text)
        self.field.setObjectName(key)
        container.layout().addWidget(self.field)


@pytest.fixture(scope="module")
def app():
    return QApplication.instance() or QApplication([])


@pytest.mark.parametrize("key", [module.KEY_RL_WIDTH, module.KEY_RL_HEIGHT])
@pytest.mark.parametrize("tab_index", [0, 1])
@pytest.mark.parametrize("saved_value", [None, 1.5])
def test_empty_required_railing_dimension_blocks_save(app, key, tab_index, saved_value):
    dialog = ValidationDialog(key, "", tab_index, saved_value)
    dialog.show()
    app.processEvents()
    try:
        # An inactive page hides its descendants visually, not explicitly.
        assert not dialog.field.isHidden()
        assert not dialog.field.parentWidget().isHidden()
        assert dialog.field.isVisible() == (tab_index == 0)
        assert dialog.tabs.widget(tab_index).isHidden() == (tab_index == 1)
        error = dialog.validator.validate_additional_inputs(key, {key: ""})
        assert error is not None
        assert "must be a numeric value" in error[1]
        saved = dict(dialog.default_input_dict)
        with patch.object(dialog, "_show_validation_errors") as warning, \
                patch.object(module, "CustomMessageBox") as message, \
                patch.object(module, "extend_cb_dynamic_keys"):
            dialog._save_inputs()
        warning.assert_called_once_with([error[1]])
        message.assert_not_called()
        assert dialog.default_input_dict == saved
    finally:
        dialog.close()


def test_valid_inputs_save_successfully(app):
    key = module.KEY_RL_WIDTH
    dialog = ValidationDialog(key, "1.5", 1, 1.5)
    dialog.show()
    app.processEvents()
    try:
        saved = dialog.default_input_dict
        with patch.object(dialog, "_show_validation_errors") as warning, \
                patch.object(module, "CustomMessageBox") as message, \
                patch.object(module, "extend_cb_dynamic_keys"):
            dialog._save_inputs()
        warning.assert_not_called()
        assert message.call_args.kwargs["title"] == "Saved"
        assert dialog.default_input_dict is saved
        assert saved == {key: 1.5}
    finally:
        dialog.close()
