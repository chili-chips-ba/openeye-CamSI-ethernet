#include <QApplication>
#include "mainwindow.h"
#include <QDebug>

int main(int argc, char *argv[])
{
    QApplication a(argc, argv);    
    MainWindow w;        
    w.show();
    w.move(10,10);
    return a.exec();
}

