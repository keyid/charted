/**
 * Copyright 2014 Google Inc. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style
 * license that can be found in the LICENSE file or at
 * https://developers.google.com/open-source/licenses/bsd
 */
part of charted.charts;

// TODO (midoringo): Handle Observable behavior.
/**
 * Transforms the ChartData base on the specified dimension columns and facts
 * columns indices. The values in the facts columns will be aggregated by the
 * tree heirarcy generated by the dimension columns.  Expand and Collapse
 * methods may be called to display different levels of aggragation.
 *
 * The output ChartData produced by transform() will contain only columns in the
 * original ChartData that were specified in dimensions or facts column indices.
 * The output column will be re-ordered first by the indices specified in the
 * dimension column indices then by the facts column indices.  The data in the
 * cells of each row will also follow this rule.
 */
class AggregationTransformer extends Observable implements ChartDataTransformer,
    ChartData {

  static const String AGGREGATION_TYPE_SUM = 'sum';
  static const String AGGREGATION_TYPE_MIN = 'min';
  static const String AGGREGATION_TYPE_MAX = 'max';
  static const String AGGREGATION_TYPE_VALID = 'valid';
  Iterable<ChartColumnSpec> columns;
  Iterable<Iterable> rows;
  List<int> _dimensionColumnIndices;
  List<int> _factsColumnIndices;
  String _aggregationType;
  AggregationModel _model;
  final Set<List> _expandedSet = new Set();
  bool _expandAllDimension = false;
  List _selectedColumns = [];
  FieldAccessor _indexFieldAccessor = (List row, int index) => row[index];

  AggregationTransformer(this._dimensionColumnIndices,
      this._factsColumnIndices,
      [String aggregationType = AGGREGATION_TYPE_SUM]) {
    _aggregationType = aggregationType;
    rows = new ObservableList();
  }

  /**
   * Transforms the ChartData base on the specified dimension columns and facts
   * columns, aggregation type and currently expanded dimensions.
   */
  ChartData transform(ChartData data) {
    assert(data.columns.length > max(_dimensionColumnIndices));
    assert(data.columns.length > max(_factsColumnIndices));

    _model = new AggregationModel(data.rows, _dimensionColumnIndices,
        _factsColumnIndices, aggregationTypes: [_aggregationType],
        dimensionAccessor: _indexFieldAccessor,
        factsAccessor: _indexFieldAccessor);
    _model.compute();

    // If user called expandAll prior to model initiation, do it now.
    if (_expandAllDimension) {
      expandAll();
    }

    _selectedColumns.addAll(_dimensionColumnIndices);
    _selectedColumns.addAll(_factsColumnIndices);

    // Process rows.
    (rows as ObservableList).clear();
    var transformedRows = [];
    for (var value in _model.valuesForDimension(_dimensionColumnIndices[0])) {
      _generateAggregatedRow(transformedRows, [value]);
    }
    (rows as ObservableList).addAll(transformedRows);

    // Process columns.
    columns = new List.generate(_selectedColumns.length, (index) =>
        data.columns.elementAt(_selectedColumns[index]));

    return this;
  }

  /**
   * Fills the aggregatedRows List with data base on the set of expanded values
   * recursively.  Currently when a dimension is expanded, rows are
   * generated for its children but not for itself.  If we want to change the
   * logic to include itself, just move the expand check around the else clause
   * and always write a row of data whether it's expanded or not.
   */
  _generateAggregatedRow(List aggregatedRows, List dimensionValues) {
    var entity = _model.facts(dimensionValues);
    var dimensionLevel = dimensionValues.length - 1;
    var currentDimValue = dimensionValues.last;

    // Dimension is not expanded at this level.  Generate data rows and fill int
    // value base on whether the column is dimension column or facts column.
    if (!_isExpanded(dimensionValues) ||
        dimensionValues.length == _dimensionColumnIndices.length) {
      aggregatedRows.add(new List.generate(_selectedColumns.length, (index) {

        // Dimension column.
        if (index < _dimensionColumnIndices.length) {
          if (index < dimensionLevel) {
            // If column index is in a higher level, write parent value.
            return dimensionValues[0];
          } else if (index == dimensionLevel) {
            // If column index is at current level, write value.
            return dimensionValues.last;
          } else {
            // If column Index is in a lower level, write empty string.
            return '';
          }
        } else {
          // Write aggregated value for facts column.
          return entity['${_aggregationType}(${_selectedColumns[index]})'];
        }
      }));
    } else {
      // Dimension is expanded, process each child dimension in the expanded
      // dimension.
      for (AggregationItem childAggregation in entity['aggregations']) {
        _generateAggregatedRow(aggregatedRows, childAggregation.dimensions);
      }
    }
  }

  /**
   * Expands a specific dimension and optionally expands all of its parent
   * dimensions.
   */
  void expand(List dimension, [bool expandParent = true]) {
    _expandAllDimension = false;
    _expandedSet.add(dimension);
    if (expandParent && dimension.length > 1) {
      Function eq = const ListEquality().equals;
      var dim = dimension.take(dimension.length - 1).toList();
      if (!_expandedSet.any((e) => eq(e, dim))) {
        expand(dim);
      }
    }
  }

  /**
   * Collapses a specific dimension and optionally collapse all of its
   * Children dimensions.
   */
  void collapse(List dimension, [bool collapseChildren = true]) {
    _expandAllDimension = false;
    if (collapseChildren) {
      Function eq = const ListEquality().equals;
      // Doing this because _expandedSet.where doesn't work.
      var collapseList = [];
      for (List dim in _expandedSet) {
        if (eq(dim.take(dimension.length).toList(), dimension)) {
          collapseList.add(dim);
        }
      }
      _expandedSet.removeAll(collapseList);
    } else {
      _expandedSet.remove(dimension);
    }
  }

  /** Expands all dimensions. */
  void expandAll() {
    if (_model != null) {
      for (var value in _model.valuesForDimension(_dimensionColumnIndices[0])) {
        _expandAll([value]);
      }
      _expandAllDimension = false;
    } else {
      _expandAllDimension = true;
    }
  }

  void _expandAll(value) {
    var entity = _model.facts(value);
    _expandedSet.add(value);
    for (AggregationItem childAggregation in entity['aggregations']) {
      _expandAll(childAggregation.dimensions);
    }
  }

  /** Collapses all dimensions. */
  void collapseAll() {
    _expandAllDimension = false;
    _expandedSet.clear();
  }

  /** Tests if specific dimension is expanded. */
  bool _isExpanded(List dimension) {
    Function eq = const ListEquality().equals;
    return _expandedSet.any((e) => eq(e, dimension));
  }
}