#ifndef BCPROPERTYEDITOR_H
#define BCPROPERTYEDITOR_H

#include <QWidget>
#include "ui_bcpropertyeditor.h"
#include "dynamiceditor.h"

#define MAX_BCS 1000

class BCPropertyEditor : public QDialog
{
  Q_OBJECT

public:
  BCPropertyEditor(QWidget *parent = 0);
  ~BCPropertyEditor();

//  Ui::bcPropertyDialog ui;
  DynamicEditor *bcPropertyDialog;

  bool touched;

private slots:
  void applySlot();
  void discardSlot();

private:

};

#endif // BCPROPERTYEDITOR_H
